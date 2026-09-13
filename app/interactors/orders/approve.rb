module Orders
  class Approve < ApplicationOrganizer
    organize ApproveOrder, Workflows::Trigger
  end
end
