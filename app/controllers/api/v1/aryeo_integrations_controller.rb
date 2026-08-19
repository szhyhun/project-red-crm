class Api::V1::AryeoIntegrationsController < Api::V1::BaseController
  before_action :set_connection, only: %i[show create validate import destroy]

  def show
    authorize @connection
    render json: { integration: serialize(@connection), recent_runs: recent_runs }
  end

  def create
    authorize @connection
    @connection.assign_attributes(api_key: params.require(:api_key), status: :connected, credentials_updated_at: Time.current)
    if @connection.save
      render json: { integration: serialize(@connection) }
    else
      render_validation_errors(@connection)
    end
  end

  def validate
    authorize @connection, :validate?
    return render json: { error: "aryeo_not_connected" }, status: :unprocessable_entity unless @connection.api_key_configured?

    Aryeo::Client.new(api_key: @connection.api_key).get("products", params: { per_page: 1 })
    @connection.update!(status: :connected, last_validated_at: Time.current)
    render json: { integration: serialize(@connection), valid: true }
  rescue Aryeo::Client::Error => error
    @connection.update!(status: :invalid) if @connection.persisted?
    render json: { error: "aryeo_validation_failed", details: error.message }, status: :unprocessable_entity
  end

  def import
    authorize @connection, :import?
    return render json: { error: "aryeo_not_connected" }, status: :unprocessable_entity unless @connection.api_key_configured?

    run = @connection.integration_import_runs.create!(organization: Current.organization, provider: :aryeo)
    AryeoImportJob.perform_later(run.id)
    render json: { import_run: serialize_run(run) }, status: :accepted
  end

  def destroy
    authorize @connection
    @connection.disconnect!
    head :no_content
  end

  private

  def set_connection
    @connection = Current.organization.integration_connections.find_or_initialize_by(provider: :aryeo)
  end

  def serialize(connection)
    {
      provider: connection.provider,
      status: connection.status,
      api_key_configured: connection.api_key_configured?,
      api_key_masked: connection.masked_api_key,
      last_validated_at: connection.last_validated_at,
      last_imported_at: connection.last_imported_at,
      endpoint_coverage: connection.endpoint_coverage
    }
  end

  def recent_runs
    @connection.integration_import_runs.order(created_at: :desc).limit(10).map { |run| serialize_run(run) }
  end

  def serialize_run(run)
    run.slice(:id, :status, :phase, :counts, :coverage, :started_at, :completed_at, :created_at).merge(errors: run.error_details)
  end
end
