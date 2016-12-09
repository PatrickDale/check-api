class Translation
  include AnnotationBase

  attribute :translation, String, presence: true, mapping: { analyzer: 'hashtag' }
  attribute :comment, String, presence: true
  attribute :from, String, presence: true
  attribute :to, String, presence: true

  validates_presence_of :translation
  validates_presence_of :comment
  validates_presence_of :from
  validates_presence_of :to

  notifies_slack on: :save,
                 if: proc { |t| t.should_notify? },
                 message: proc { |t| data = t.annotated.data(t.context); "*#{t.current_user.name}* translated <#{t.origin}/project/#{t.context_id}/media/#{t.annotated_id}|#{data['title']}> from #{t.from} to #{t.to}\n> #{t.translation}" },
                 channel: proc { |t| t.context.setting(:slack_channel) || t.current_team.setting(:slack_channel) },
                 webhook: proc { |t| t.current_team.setting(:slack_webhook) }

  def content
    { translation: self.translation, comment: self.comment, from: self.from, to: self.to }.to_json
  end
end
