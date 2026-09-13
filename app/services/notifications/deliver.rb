module Notifications
  class Deliver < ApplicationOrganizer
    organize PrepareDelivery, SendDelivery
  end
end
