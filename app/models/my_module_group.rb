class MyModuleGroup < ActiveRecord::Base
  include SearchableModel

  auto_strip_attributes :name, nullify: false
  validates :name,
            presence: true,
            length: { maximum: Constants::NAME_MAX_LENGTH }
  validates :experiment, presence: true

  belongs_to :experiment, inverse_of: :my_module_groups
  belongs_to :created_by, foreign_key: 'created_by_id', class_name: 'User'
  has_many :my_modules, inverse_of: :my_module_group, dependent: :nullify

  def self.search(user, include_archived, query = nil, page = 1)
    exp_ids =
      Experiment
      .search(user, include_archived, nil, Constants::SEARCH_NO_LIMIT)
      .select("id")


    if query
      a_query = query.strip
      .gsub("_","\\_")
      .gsub("%","\\%")
      .split(/\s+/)
      .map {|t|  "%" + t + "%" }
    else
      a_query = query
    end

    new_query = MyModuleGroup
      .distinct
      .where("my_module_groups.experiment_id IN (?)", exp_ids)
      .where_attributes_like("my_module_groups.name", a_query)

    # Show all results if needed
    if page == Constants::SEARCH_NO_LIMIT
      new_query
    else
      new_query
        .limit(Constants::SEARCH_LIMIT)
        .offset((page - 1) * Constants::SEARCH_LIMIT)
    end
  end

  def ordered_modules
    my_modules.order(workflow_order: :asc)
  end

  def deep_clone_to_experiment(current_user, experiment)
    clone = MyModuleGroup.new(
      name: name,
      created_by: created_by,
      experiment: experiment
    )

    # Get clones of modules from this group, save them as hash
    cloned_modules = ordered_modules.each_with_object({}) do |m, hash|
      hash[m.id] = m.deep_clone_to_experiment(current_user, experiment)
      hash
    end

    ordered_modules.each do |m|
      # Copy connections
      m.inputs.each do |inp|
        Connection.create(
          input_id: cloned_modules[inp[:input_id]].id,
          output_id: cloned_modules[inp[:output_id]].id
        )
      end

      # Copy remaining variables
      cloned_module = cloned_modules[m.id]
      cloned_module.my_module_group = self
      cloned_module.created_by = m.created_by
      cloned_module.workflow_order = m.workflow_order
    end

    clone.my_modules << cloned_modules.values
    clone.save
    clone
  end
end
