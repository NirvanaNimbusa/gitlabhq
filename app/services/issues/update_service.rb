module Issues
  class UpdateService < Issues::BaseService
    def execute(issue)
      update(issue)
    end

    def handle_changes(issue, options = {})
      if have_changes?(issue, options)
        task_service.mark_as_done(issue, current_user)
      end

      if issue.previous_changes.include?('milestone_id')
        create_milestone_note(issue)
      end

      if issue.previous_changes.include?('assignee_id')
        create_assignee_note(issue)
        notification_service.reassigned_issue(issue, current_user)
        task_service.reassigned_issue(issue, current_user)
      end
    end

    def reopen_service
      Issues::ReopenService
    end

    def close_service
      Issues::CloseService
    end

    private

    def have_changes?(issue, options = {})
      valid_attrs = [:title, :description, :assignee_id, :milestone_id]

      attrs_changed = valid_attrs.any? do |attr|
        issue.previous_changes.include?(attr.to_s)
      end

      old_labels = options[:old_labels]
      labels_changed = old_labels && issue.labels != old_labels

      if attrs_changed || labels_changed
        task_service.mark_as_done(issue, current_user)
      end
    end
  end
end
