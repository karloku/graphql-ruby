require 'spec_helper'

describe GraphQL::EnumType do
  let(:enum) { DairyAnimalEnum }

  it 'coerces names to underlying values' do
    assert_equal("YAK", enum.coerce_input("YAK"))
    assert_equal(1, enum.coerce_input("COW"))
  end

  it "coerces result values to value's value" do
    assert_equal("YAK", enum.coerce_result("YAK"))
    assert_equal("COW", enum.coerce_result(1))
  end

  it 'has value description' do
    assert_equal("Animal with horns", enum.values['GOAT'].description)
  end
end
