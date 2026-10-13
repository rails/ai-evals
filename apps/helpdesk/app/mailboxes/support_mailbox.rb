class SupportMailbox < ApplicationMailbox
  def process
    IncomingSupportEmail.new(mail).process
  end
end
