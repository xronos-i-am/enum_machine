# frozen_string_literal: true

module EnumMachine
  module BuildClass

    def self.call(enum_values:, i18n_scope:, machine: nil)
      Class.new do
        define_singleton_method(:machine) { machine } if machine
        define_singleton_method(:values) { enum_values }

        if i18n_scope
          def self.values_for_form(specific_values = nil) # rubocop:disable Gp/OptArgParameters
            (specific_values || values).map { |v| [human_name_for(v), v] }
          end

          class_eval <<-RUBY, __FILE__, __LINE__ + 1
            # def self.human_name_for(name)
            #   ::I18n.t(name, scope: "enums.test_model", default: name)
            # end

            def self.human_name_for(name)
              ::I18n.t(name, scope: "enums.#{i18n_scope}", default: name)
            end
          RUBY
        end

        enum_values.each do |enum_value|
          const_set enum_value.underscore.upcase, enum_value.freeze
        end

        private_class_method def self.const_missing(name)
          name_s = name.to_s
          return super unless name_s.include?('__')

          const_set name_s, name_s.split('__').map { |i| const_get(i) }.freeze
        end
      end
    end

  end
end
