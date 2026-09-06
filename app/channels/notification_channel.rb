# One stream per person rather than one per conversation: the portal needs to
# know about a message in any thread it is not currently looking at, and a
# per-user stream means the server decides who may hear something once, at
# broadcast time, instead of authorizing a subscription per thread.
class NotificationChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user
  end
end
