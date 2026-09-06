class CreateBoardLabels < ActiveRecord::Migration[8.0]
  LABEL_COLORS = %w[#e8f7ed #e8f0ff #f1eafa #fbf4d7 #fde7e3 #e5f5f5].freeze

  def up
    create_table :board_labels do |t|
      t.references :board, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color, null: false, default: LABEL_COLORS.first
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :board_labels, "board_id, LOWER(name)", unique: true,
              name: "index_board_labels_on_board_id_and_lower_name"

    create_table :workflow_task_labels do |t|
      t.references :workflow_task, null: false, foreign_key: true
      t.references :board_label, null: false, foreign_key: true
      t.timestamps
    end
    add_index :workflow_task_labels, %i[workflow_task_id board_label_id], unique: true,
              name: "index_workflow_task_labels_on_task_and_label"

    backfill_board_labels!

    remove_index :workflow_tasks, name: "index_workflow_tasks_on_labels", if_exists: true
    remove_column :workflow_tasks, :labels
  end

  def down
    add_column :workflow_tasks, :labels, :string, array: true, null: false, default: []
    restore_task_label_names!

    remove_index :workflow_task_labels, name: "index_workflow_task_labels_on_task_and_label", if_exists: true
    drop_table :workflow_task_labels
    remove_index :board_labels, name: "index_board_labels_on_board_id_and_lower_name", if_exists: true
    drop_table :board_labels
    add_index :workflow_tasks, :labels, using: :gin
  end

  private

  def backfill_board_labels!
    workflow_task_class = migration_class(:workflow_tasks)
    board_label_class = migration_class(:board_labels)
    workflow_task_label_class = migration_class(:workflow_task_labels)
    workflow_task_class.reset_column_information
    board_label_class.reset_column_information
    workflow_task_label_class.reset_column_information

    labels_by_key = {}
    next_positions = Hash.new do |positions, board_id|
      positions[board_id] = board_label_class.where(board_id:).maximum(:position).to_i
    end

    workflow_task_class.find_each do |task|
      Array(task.labels).map { |label| label.to_s.strip }.reject(&:blank?).uniq.each do |name|
        key = [ task.board_id, name.downcase ]
        label = labels_by_key[key] ||= board_label_class.where(board_id: task.board_id)
                                                    .find_by("LOWER(name) = ?", name.downcase)
        unless label
          position = next_positions[task.board_id]
          label = board_label_class.create!(board_id: task.board_id, name:, position:,
                                            color: LABEL_COLORS[position % LABEL_COLORS.length])
          labels_by_key[key] = label
          next_positions[task.board_id] += 1
        end

        workflow_task_label_class.create!(workflow_task_id: task.id, board_label_id: label.id)
      end
    end
  end

  def restore_task_label_names!
    workflow_task_class = migration_class(:workflow_tasks)
    board_label_class = migration_class(:board_labels)
    workflow_task_label_class = migration_class(:workflow_task_labels)
    workflow_task_class.reset_column_information
    board_label_class.reset_column_information
    workflow_task_label_class.reset_column_information

    names_by_label_id = board_label_class.pluck(:id, :name).to_h
    workflow_task_label_class.order(:workflow_task_id, :id).pluck(:workflow_task_id, :board_label_id)
                             .group_by(&:first).each do |task_id, rows|
      labels = rows.filter_map { |(_, label_id)| names_by_label_id[label_id] }
      workflow_task_class.find(task_id).update_columns(labels:)
    end
  end

  def migration_class(table_name)
    Class.new(ActiveRecord::Base) do
      self.table_name = table_name.to_s
    end
  end
end
