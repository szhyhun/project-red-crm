module Integrations
  module Aryeo
    module Organizers
      class ImportResource < ApplicationOrganizer
        organize Integrations::Aryeo::Actions::ResolveResourceConflict,
                 Integrations::Aryeo::Actions::DispatchResource,
                 Integrations::Aryeo::Actions::ArchiveResource,
                 Integrations::Aryeo::Actions::CountResource
      end
    end
  end
end
