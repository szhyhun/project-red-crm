class ApplicationPolicy
  # The question set every policy answers. `view/create/update/destroy` are the
  # familiar CRUD questions; `manage` is separate because "may edit this record"
  # and "may change how this resource works for everyone" are different
  # permissions that were previously spelled three different ways.
  CAPABILITIES = %i[view create update destroy manage].freeze

  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def view?
    false
  end

  def create?
    false
  end

  def update?
    false
  end

  def destroy?
    false
  end

  def manage?
    false
  end

  # Kept as aliases so the existing `authorize record, :show?` call sites and
  # Pundit's own action-name inference keep working unchanged.
  def index?
    view?
  end

  def show?
    view?
  end

  # Serialized onto records and into the session payload so the interface stops
  # re-deriving these rules from the user's role. This is a hint for rendering,
  # never the boundary: the server still authorizes every request on its own.
  def capabilities
    self.class::CAPABILITIES.select { |capability| public_send(:"#{capability}?") }
  end

  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NotDefinedError
    end
  end
end
