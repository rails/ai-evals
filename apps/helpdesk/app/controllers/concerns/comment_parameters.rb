module CommentParameters
  extend ActiveSupport::Concern

  private

  def normalize_comment_parameters!(comment)
    raise ApiError.new(422, "Comment must be an object") unless comment.is_a?(Hash)
    comment["body"] = comment["body"].to_s
    if comment.key?("public") && ![true, false].include?(comment["public"])
      raise ApiError.new(422, "Comment visibility must be a boolean")
    end
  end
end
