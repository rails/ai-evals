class Question < ApplicationRecord
  belongs_to :quiz
  has_many :answers, dependent: :delete_all

  scope :active, -> { where(active: true) }

  before_validation :normalize_options
  before_create :set_position
  before_destroy :ensure_not_on_screen, prepend: true

  validates :body, presence: true
  validate :validate_options

  # Options come from forms as an indexed hash ({"0" => {title:, correct:}, ...})
  # or as an array; we always store a JSON array of {"title", "correct"} hashes.
  def options=(value)
    value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
    value = value.values if value.is_a?(Hash)
    super(Array(value).map { |opt| opt.to_h.stringify_keys.slice("title", "correct") })
  end

  def option_titles = options.map { it["title"] }

  def correct_option?(index) = !!options.dig(index.to_i, "correct")

  def correct_indexes = options.each_index.select { correct_option?(it) }

  def move!(direction)
    siblings = quiz.questions.to_a
    index = siblings.index(self)
    target = (direction.to_s == "up") ? index - 1 : index + 1
    return if target.negative? || target >= siblings.size

    siblings[index], siblings[target] = siblings[target], siblings[index]
    transaction do
      siblings.each_with_index { |q, i| q.update_column(:position, i) unless q.position == i }
    end
  end

  private

  def normalize_options
    self.options = (options || []).filter_map do |opt|
      title = opt["title"].to_s.strip
      next if title.blank?
      {"title" => title, "correct" => ActiveModel::Type::Boolean.new.cast(opt["correct"]) || false}
    end
  end

  def validate_options
    errors.add(:base, "Add at least two options") if options.size < 2
    errors.add(:base, "Mark at least one option as correct") if options.none? { it["correct"] }
  end

  def ensure_not_on_screen
    return if destroyed_by_association || !Run.running.exists?(current_question_id: id)

    errors.add(:base, "This question is on screen in a running game, so it can't be deleted")
    throw :abort
  end

  def set_position
    self.position = (quiz.questions.maximum(:position) || -1) + 1
  end
end
