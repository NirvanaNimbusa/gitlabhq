# frozen_string_literal: true

module GitlabScriptTagHelper
  # Override the default ActionView `javascript_include_tag` helper to support page specific deferred loading.
  # PLEASE NOTE: `defer` is also critical so that we don't run JavaScript entrypoints before the DOM is ready.
  # Please see https://gitlab.com/groups/gitlab-org/-/epics/4538#note_432159769.
  # The helper also makes sure the `nonce` attribute is included in every script when the content security
  # policy is enabled.
  def javascript_include_tag(*sources)
    super(*sources, defer: true, nonce: true)
  end

  # The helper makes sure the `nonce` attribute is included in every script when the content security
  # policy is enabled.
  def javascript_tag(content_or_options_with_block = nil, html_options = {})
    if content_or_options_with_block.is_a?(Hash)
      content_or_options_with_block[:nonce] = true
    else
      html_options[:nonce] = true
    end

    super
  end
end
