class Ticket < ApplicationRecord
  self.filter_attributes += [:email_reply_token]
  belongs_to :account
  belongs_to :group, optional: true
  belongs_to :requester, class_name: "User"
  belongs_to :assignee, class_name: "User", optional: true
  belongs_to :merged_into, class_name: "Ticket", optional: true
  has_many :comments, -> { order(:id) }
  EDITABLE_STATUSES = %w[open pending solved].freeze
  STATUSES = (EDITABLE_STATUSES + ["closed"]).freeze

  normalizes :subject, with: ->(subject) { subject.strip }

  validates :subject, presence: true, length: {maximum: 200}
  validates :status, inclusion: {in: STATUSES}
  validates :priority, inclusion: {in: %w[normal high]}
  validate :assignee_is_eligible, if: -> { new_record? || will_save_change_to_assignee_id? }
  validate :assignee_belongs_to_group

  def closed? = status == "closed"

  private

  def assignee_is_eligible
    errors.add(:assignee, :invalid) if assignee && (!assignee.staff? || !assignee.eligible?)
  end

  def assignee_belongs_to_group
    if account && group_id && assignee_id && !account.group_memberships.exists?(group_id: group_id, user_id: assignee_id)
      errors.add(:assignee, "must belong to the ticket's group")
    end
  end
end
