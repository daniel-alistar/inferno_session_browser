# frozen_string_literal: true
module InfernoSessionBrowser
  class Registry
    def suite(id)
      Inferno::Repositories::TestSuites.new.find(id)
    end

    def runnable(type, id)
      repository = { 'suite' => 'TestSuites', 'group' => 'TestGroups', 'test' => 'Tests' }.fetch(type)
      Inferno::Repositories.const_get(repository).new.find(id)
    end
  end
end
