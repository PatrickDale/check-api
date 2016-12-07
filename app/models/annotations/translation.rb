class Translation
  include AnnotationBase

  attribute :translation, String, presence: true, mapping: { analyzer: 'hashtag' }
  attribute :note, String, presence: true, mapping: { analyzer: 'hashtag' }
  validates_presence_of :text

  notifies_slack on: :save,
                 if: proc { |c| c.should_notify? },
                 message: proc { |c| data = c.annotated.data(c.context); "*#{c.current_user.name}* translated <#{c.origin}/project/#{c.context_id}/media/#{c.annotated_id}|#{data['title']}>\n> #{c.translation}" },
                 channel: proc { |c| c.context.setting(:slack_channel) || c.current_team.setting(:slack_channel) },
                 webhook: proc { |c| c.current_team.setting(:slack_webhook) }

  def content
    { translation: self.translation, note: self.note }.to_json
  end
end
