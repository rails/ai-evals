class GroupMembership < ApplicationRecord
  belongs_to :account
  belongs_to :group
  belongs_to :user

  validates :user_id, uniqueness: {scope: :group_id}
  validates :default, inclusion: {in: [true, false]}
  validate :user_is_eligible, if: -> { new_record? || will_save_change_to_user_id? }

  private

  def user_is_eligible
    errors.add(:user, "must be an active staff member") if user && (!user.staff? || !user.eligible?)
  end
end
