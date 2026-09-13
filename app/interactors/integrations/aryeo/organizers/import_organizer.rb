module Integrations
  module Aryeo
    module Organizers
      class ImportOrganizer < ApplicationOrganizer
        organize Integrations::Aryeo::Actions::StartImport,
                 Integrations::Aryeo::Actions::ImportSelectedCollections,
                 Integrations::Aryeo::Actions::ReconcileImportedDelivery,
                 Integrations::Aryeo::Actions::CompleteImport
      end
    end
  end
end
