# Demo quiz for local development: bin/rails db:seed
# (skipped in production, where `db:prepare` seeds a freshly created database)
return if Rails.env.production?

quiz = Quiz.find_or_create_by!(title: "Web dev trivia") { it.winners_count = 3 }

if quiz.questions.empty?
  [
    ["Who created the Ruby language?", ["Yukihiro Matsumoto", true], ["David Heinemeier Hansson", false], ["Guido van Rossum", false], ["Aaron Patterson", false]],
    ["When was Ruby first released to the public?", ["1991", false], ["1995", true], ["2000", false], ["2004", false]],
    ["What does [1, 2, 3].sum { it * 2 } return?", ["6", false], ["12", true], ["NoMethodError", false], ["[2, 4, 6]", false]],
    ["Which HTTP status code means \"Too Many Requests\"?", ["418", false], ["429", true], ["503", false], ["409", false]],
    ["Which protocol keeps a two-way connection between a browser and a server?", ["WebSocket", true], ["SMTP", false], ["FTP", false], ["DNS", false]]
  ].each do |body, *options|
    quiz.questions.create!(body:, options: options.map { |title, correct| {title:, correct:} })
  end
end

puts "Quiz ##{quiz.id}: #{quiz.questions.count} questions"
