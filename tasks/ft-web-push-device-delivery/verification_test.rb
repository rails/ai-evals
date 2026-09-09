require "web-push"

vapid = WebPush.generate_key
ENV["VAPID_PUBLIC_KEY"], ENV["VAPID_PRIVATE_KEY"] = vapid.public_key, vapid.private_key
ENV["VAPID_SUBJECT"] ||= "mailto:support@example.com"

require "test_helper"

module PinnedAddress
  def request_signature_from_request(net_http, request, body = nil)
    super.tap { |signature| signature.ipaddr = net_http.instance_variable_get(:@ipaddr) }
  end
end
WebMock::NetHTTPUtility.singleton_class.prepend PinnedAddress

class VerifierTest < ActionDispatch::IntegrationTest
  PUBLIC_IP = "142.250.185.206"
  PRIVATE_IP = "10.0.0.5"
  LOOPBACK = "127.0.0.1"

  setup do
    stub_dns_resolution(PUBLIC_IP)
    @pushes, @gone = [], []
    stub_request(:post, %r{\Ahttps://(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|web\.push\.apple\.com|#{PUBLIC_IP})[:/]}).to_return do |request|
      @pushes << { path: request.uri.path, body: request.body.to_s.b, encoding: request.headers["Content-Encoding"], ipaddr: request.ipaddr }
      { status: @gone.include?(request.uri.path) ? 410 : 201, body: "" }
    end
    @account, @card, @kevin, @jason, @david = accounts("37s"), cards(:logo), users(:kevin), users(:jason), users(:david)
    @card.watch_by(@kevin)
    @card.unwatch_by(@jason)
    @kevin.notifications.where(card: @card).destroy_all
  end

  test "what lands in the tray reaches each of that person's devices, once, and nobody else's" do
    phone = enroll(@kevin, device("fcm.googleapis.com", "/fcm/send/"))
    laptop = enroll(@kevin, device("updates.push.services.mozilla.com", "/wpush/v2/"))
    other = enroll(@jason, device("web.push.apple.com", "/"))

    recipients = comment_on_card("Great work on the logo, nearly there")
    await { pushes_to(phone).any? && pushes_to(laptop).any? }

    assert_includes recipients, @kevin
    assert_not_includes recipients, @jason
    assert_equal 1, pushes_to(phone).size
    assert_equal 1, pushes_to(laptop).size
    assert_empty pushes_to(other)
  end

  test "a push says what the tray says and opens the card" do
    phone = enroll(@kevin, device("fcm.googleapis.com", "/fcm/send/"))

    comment_on_card("Ship it after the kerning fix")
    await { pushes_to(phone).any? }

    text = decrypt(pushes_to(phone).sole, phone)
    event = @kevin.notifications.find_by!(card: @card).source
    assert_includes text, ApplicationController.helpers.event_notification_title(event)
    assert_includes text, ApplicationController.helpers.event_notification_body(event)
    assert opens_the_card?(text, @kevin), "nothing in the push opens the card: #{text[0, 300].inspect}"
  end

  test "a second thing on the same card pushes again" do
    phone = enroll(@kevin, device("fcm.googleapis.com", "/fcm/send/"))
    comment_on_card("First comment")
    await { pushes_to(phone).any? }
    assert_equal 1, pushes_to(phone).size

    comment_on_card("Second comment, same card")
    await { pushes_to(phone).size > 1 }

    assert_equal 2, pushes_to(phone).size
  end

  test "turning push on twice from the same device does not double the pushes" do
    phone = enroll(@kevin, device("fcm.googleapis.com", "/fcm/send/"))
    enroll(@kevin, phone)

    comment_on_card("Once is enough")
    await { pushes_to(phone).any? }
    await(timeout: 1) { pushes_to(phone).size > 1 }

    assert_equal 1, pushes_to(phone).size
  end

  test "a device that is gone stops getting pushed" do
    phone = enroll(@kevin, device("fcm.googleapis.com", "/fcm/send/"))
    laptop = enroll(@kevin, device("updates.push.services.mozilla.com", "/wpush/v2/"))
    @gone << URI(phone[:endpoint]).path
    comment_on_card("The phone was reset yesterday")
    await { pushes_to(phone).any? && pushes_to(laptop).any? }
    await(timeout: 1) { pushes_to(phone).size > 1 }
    assert_equal 1, pushes_to(phone).size

    comment_on_card("And here is another comment")
    await { pushes_to(laptop).size > 1 }
    await(timeout: 1) { pushes_to(phone).size > 1 }

    assert_equal 2, pushes_to(laptop).size
    assert_equal 1, pushes_to(phone).size
  end

  test "a device cannot point a push at our own network" do
    reached = []
    stub_request(:post, %r{\Ahttps://intranet\.example\.test/}).to_return { |request| reached << request; { status: 201 } }
    phone = enroll(@kevin, device("fcm.googleapis.com", "/fcm/send/"))
    stub_dns_resolution(PRIVATE_IP)
    post "#{user_path(@kevin)}/push_subscriptions", params: { push_subscription: subscription_of(device("intranet.example.test", "/push/")) }, as: :json
    stub_dns_resolution(PUBLIC_IP, LOOPBACK)

    comment_on_card("Nothing here should reach the intranet")
    await(timeout: 2) { reached.any? }

    assert_empty reached
    assert pushes_to(phone).all? { |push| push[:ipaddr] == PUBLIC_IP }, "the push went by name, not to the address that was checked"
  end

  test "a device cannot be signed up for someone else's notifications" do
    logout_and_sign_in_as @jason
    phone = device("fcm.googleapis.com", "/fcm/send/")
    post "#{user_path(@kevin)}/push_subscriptions", params: { push_subscription: subscription_of(phone) }, as: :json

    recipients = comment_on_card("Only Kevin should hear this")
    await(timeout: 2) { pushes_to(phone).any? }

    assert_includes recipients, @kevin
    assert_empty pushes_to(phone)
  end

  private
    def device(host, prefix)
      { endpoint: "https://#{host}#{prefix}#{SecureRandom.hex(8)}", key: WebPush.generate_key, auth: SecureRandom.random_bytes(16) }
    end

    def subscription_of(device)
      { endpoint: device[:endpoint], p256dh_key: device[:key].public_key, auth_key: Base64.urlsafe_encode64(device[:auth]) }
    end

    def enroll(user, device)
      logout_and_sign_in_as user
      post "#{user_path(user)}/push_subscriptions", params: { push_subscription: subscription_of(device) }, as: :json
      assert_includes 200..399, response.status
      device
    end

    def comment_on_card(body)
      started = Time.current
      perform_enqueued_jobs { Current.set(account: @account, user: @david) { @card.comments.create!(body: body, creator: @david) } }
      Notification.where(card: @card).where(updated_at: started..).map(&:user).uniq
    end

    def pushes_to(device) = @pushes.select { |push| push[:path] == URI(device[:endpoint]).path }

    def decrypt(push, device)
      raise "Content-Encoding is #{push[:encoding].inspect}, not aes128gcm" unless push[:encoding].to_s.casecmp?("aes128gcm")
      body, key = push[:body], device[:key].curve
      salt, idlen = body.byteslice(0, 16), body.getbyte(20)
      server_public = body.byteslice(21, idlen)
      ciphertext = body.byteslice(21 + idlen, body.bytesize)
      shared = key.dh_compute_key(OpenSSL::PKey::EC::Point.new(OpenSSL::PKey::EC::Group.new("prime256v1"), OpenSSL::BN.new(server_public, 2)))
      prk = OpenSSL::KDF.hkdf(shared, salt: device[:auth], info: "WebPush: info\0" + key.public_key.to_bn.to_s(2) + server_public, hash: "SHA256", length: 32)
      cipher = OpenSSL::Cipher.new("aes-128-gcm").decrypt
      cipher.key = OpenSSL::KDF.hkdf(prk, salt: salt, info: "Content-Encoding: aes128gcm\0", hash: "SHA256", length: 16)
      cipher.iv = OpenSSL::KDF.hkdf(prk, salt: salt, info: "Content-Encoding: nonce\0", hash: "SHA256", length: 12)
      cipher.auth_tag = ciphertext.byteslice(-16, 16)
      (cipher.update(ciphertext.byteslice(0, ciphertext.bytesize - 16)) + cipher.final).sub(/[\x01\x02]\x00*\z/n, "").force_encoding("UTF-8")
    end

    def await(timeout: 5)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      sleep 0.1 until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    end

    def opens_the_card?(text, user)
      logout_and_sign_in_as user
      links = text.scan(%r{https?://[^\s"'\\<>]+}) + text.scan(%r{(?<=["'\s])/[A-Za-z0-9_\-./#?=&]+})
      links.map { |link| link.split("#").first }.uniq.any? do |link|
        get URI(link).path
        follow_redirect! while response.redirect?
        response.successful? && response.media_type == "text/html" && response.parsed_body.text.include?(@card.title)
      end
    end
end
