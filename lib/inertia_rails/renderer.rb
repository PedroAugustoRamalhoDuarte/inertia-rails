require 'net/http'
require 'json'
require_relative "inertia_rails"

module InertiaRails
  class Renderer
    attr_reader(
      :component,
      :configuration,
      :controller,
      :props,
      :view_data,
      :encrypt_history,
      :clear_history
    )

    def initialize(component, controller, request, response, render_method, props: nil, view_data: nil, deep_merge: nil, encrypt_history: nil, clear_history: nil)
      @component = component.is_a?(TrueClass) ? "#{controller.controller_path}/#{controller.action_name}" : component
      @controller = controller
      @configuration = controller.__send__(:inertia_configuration)
      @request = request
      @response = response
      @render_method = render_method
      @props = props || controller.__send__(:inertia_view_assigns)
      @view_data = view_data || {}
      @deep_merge = !deep_merge.nil? ? deep_merge : configuration.deep_merge_shared_data
      @encrypt_history = !encrypt_history.nil? ? encrypt_history : configuration.encrypt_history
      @clear_history = clear_history || false
    end

    def render
      @response.set_header('Vary', 'X-Inertia')
      if @request.headers['X-Inertia']
        @response.set_header('X-Inertia', 'true')
        @render_method.call json: page, status: @response.status, content_type: Mime[:json]
      else
        return render_ssr if configuration.ssr_enabled rescue nil
        @render_method.call template: 'inertia', layout: layout, locals: view_data.merge(page: page)
      end
    end

    private

    def render_ssr
      uri = URI("#{configuration.ssr_url}/render")
      res = JSON.parse(Net::HTTP.post(uri, page.to_json, 'Content-Type' => 'application/json').body)

      controller.instance_variable_set("@_inertia_ssr_head", res['head'].join.html_safe)
      @render_method.call html: res['body'].html_safe, layout: layout, locals: view_data.merge(page: page)
    end

    def layout
      layout = configuration.layout
      layout.nil? ? true : layout
    end

    def shared_data
      controller.__send__(:inertia_shared_data)
    end

    # Cast props to symbol keyed hash before merging so that we have a consistent data structure and
    # avoid duplicate keys after merging.
    #
    # Functionally, this permits using either string or symbol keys in the controller. Since the results
    # is cast to json, we should treat string/symbol keys as identical.
    def merge_props(shared_data, props)
      @deep_merge ?
        shared_data.deep_symbolize_keys.deep_merge(props.deep_symbolize_keys)
        : shared_data.symbolize_keys.merge(props.symbolize_keys)
    end

    def computed_props
      _props = merge_props(shared_data, props).select do |key, prop|
        if rendering_partial_component?
          key.in?(partial_keys) || prop.is_a?(AlwaysProp)
        else
          !prop.is_a?(IgnoreFirstLoadProp)
        end
      end

      deep_transform_values(
        _props,
        lambda do |prop|
          prop.respond_to?(:call) ? controller.instance_exec(&prop) : prop
        end
      )
    end

    def page
      default_page = {
        component: component,
        props: computed_props,
        url: @request.original_fullpath,
        version: configuration.version,
        encryptHistory: encrypt_history,
        clearHistory: clear_history,
      }

      deferred_props = deferred_props_keys
      default_page[:deferredProps] = deferred_props if deferred_props.present?

      merge_props = merge_props_keys
      default_page[:mergeProps] = merge_props if merge_props.present?

      default_page
    end

    def deep_transform_values(hash, proc)
      return proc.call(hash) unless hash.is_a? Hash

      hash.transform_values {|value| deep_transform_values(value, proc)}
    end

    def deferred_props_keys
      return if rendering_partial_component?

      @props.each_with_object({}) do |(key, prop), result|
        (result[prop.group] ||= []) << key if prop.is_a?(DeferProp)
      end
    end

    def merge_props_keys
      @props.each_with_object([]) do |(key, prop), result|
        if prop.class.include?(MergeableProp) && prop.merge? && reset_keys.exclude?(key)
          result << key
        end
      end
    end

    def partial_keys
      @partial_keys ||= (@request.headers['X-Inertia-Partial-Data'] || '').split(',').compact.map(&:to_sym)
    end

    def reset_keys
      @reset_keys ||= (@request.headers['X-Inertia-Reset'] || '').split(',').compact.map(&:to_sym)
    end

    def rendering_partial_component?
      @request.inertia_partial? && @request.headers['X-Inertia-Partial-Component'] == component
    end
  end
end
