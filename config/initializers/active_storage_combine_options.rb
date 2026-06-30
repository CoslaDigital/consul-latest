# Removing this code will make ActiveStorage legacy URLs generated with
# Rails 5.2 (used in Consul Democracy 1.4 and Consul Democracy 1.5)
# inaccessible, resulting in an exception.
Rails.application.config.after_initialize do
  mod = Module.new do
    private

      def operations
        unless transformations.key?(:combine_options) || transformations.key?("combine_options")
          return super
        end

        unwrapped = transformations.each_with_object({}) do |(name, argument), hash|
          if name.to_s == "combine_options"
            hash.merge!(argument)
          else
            hash[name] = argument
          end
        end

        begin
          original = @transformations
          @transformations = unwrapped
          super
        ensure
          @transformations = original
        end
      end
  end

  ActiveStorage::Transformers::ImageProcessingTransformer.prepend(mod)
end
