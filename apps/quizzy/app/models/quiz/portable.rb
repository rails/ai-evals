# Export and import of a quiz's structure (title, questions and their options) as JSON,
# so a quiz can be reused elsewhere. Settings and games stay out of the file.
#
#   {
#     "title": "Ruby trivia",
#     "questions": [
#       {"text": "Who created Ruby?", "active": true,
#        "options": [{"text": "Matz", "correct": true}, {"text": "DHH", "correct": false}]}
#     ]
#   }
module Quiz::Portable
  extend ActiveSupport::Concern

  class ImportError < StandardError; end

  class_methods do
    # Creates a new quiz from the JSON text; all or nothing
    def import!(json)
      data = JSON.parse(json)
      raise ImportError, "The file must be a JSON object with \"title\" and \"questions\"" unless data.is_a?(Hash)

      questions = data["questions"]
      raise ImportError, "\"questions\" must be a list" unless questions.nil? || questions.is_a?(Array)

      transaction do
        quiz = create!(title: data["title"].to_s)
        Array(questions).each.with_index(1) do |question, number|
          raise ImportError, "Question #{number} must be an object" unless question.is_a?(Hash)
          options = question["options"]
          raise ImportError, "Question #{number}: \"options\" must be a list of objects" unless options.is_a?(Array) && options.all?(Hash)

          record = quiz.questions.new(
            body: question["text"].to_s,
            active: question.fetch("active", true) != false,
            options: options.map { {"title" => it["text"].to_s, "correct" => it["correct"] == true} }
          )
          raise ImportError, "Question #{number}: #{record.errors.full_messages.to_sentence}" unless record.save
        end
        quiz
      end
    rescue JSON::ParserError
      raise ImportError, "This is not valid JSON"
    rescue ActiveRecord::RecordInvalid => error
      raise ImportError, error.record.errors.full_messages.to_sentence
    end
  end

  def export
    {
      "title" => title,
      "questions" => questions.map do |question|
        {
          "text" => question.body,
          "active" => question.active,
          "options" => question.options.map { {"text" => it["title"], "correct" => it["correct"]} }
        }
      end
    }
  end
end
