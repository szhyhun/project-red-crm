module Orders
  class Approve < ApplicationOrganizer
    organize ApproveOrder, EnqueueWorkflow
  end
end
