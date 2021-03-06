require 'spec_helper'

describe GraphQL::Query do
  let(:query_string) { %|
    query getFlavor($cheeseId: Int!) {
      brie: cheese(id: 1)   { ...cheeseFields, taste: flavor },
      cheese(id: $cheeseId)  {
        __typename,
        id,
        ...cheeseFields,
        ... edibleFields,
        ... on Cheese { cheeseKind: flavor },
      }
      fromSource(source: COW) { id }
      fromSheep: fromSource(source: SHEEP) { id }
      firstSheep: searchDairy(product: [{source: SHEEP}]) {
        __typename,
        ... dairyFields,
        ... milkFields
      }
      favoriteEdible { __typename, fatContent }
    }
    fragment cheeseFields on Cheese { flavor }
    fragment edibleFields on Edible { fatContent }
    fragment milkFields on Milk { source }
    fragment dairyFields on AnimalProduct {
       ... on Cheese { flavor }
       ... on Milk   { source }
    }
  |}
  let(:debug) { false }
  let(:operation_name) { nil }
  let(:query_variables) { {"cheeseId" => 2} }
  let(:schema) { DummySchema }
  let(:query) { GraphQL::Query.new(
    schema,
    query_string,
    variables: query_variables,
    debug: debug,
    operation_name: operation_name,
  )}
  let(:result) { query.result }
  describe '#result' do
    it 'returns fields on objects' do
      expected = {"data"=> {
          "brie" =>   { "flavor" => "Brie", "taste" => "Brie" },
          "cheese" => {
            "__typename" => "Cheese",
            "id" => 2,
            "flavor" => "Gouda",
            "fatContent" => 0.3,
            "cheeseKind" => "Gouda",
          },
          "fromSource" => [{ "id" => 1 }, {"id" => 2}],
          "fromSheep"=>[{"id"=>3}],
          "firstSheep" => { "__typename" => "Cheese", "flavor" => "Manchego" },
          "favoriteEdible"=>{"__typename"=>"Milk", "fatContent"=>0.04},
      }}
      assert_equal(expected, result)
    end

    describe "when it hits null objects" do
      let(:query_string) {%|
        {
          maybeNull {
            cheese {
              flavor,
              similarCheese(source: [SHEEP]) { flavor }
            }
          }
        }
      |}

      it "skips null objects" do
        expected = {"data"=> {
          "maybeNull" => { "cheese" => nil }
        }}
        assert_equal(expected, result)
      end
    end
  end

  it 'exposes fragments' do
    assert_equal(GraphQL::Language::Nodes::FragmentDefinition, query.fragments['cheeseFields'].class)
  end

  it 'correctly identifies parse error location' do
    # "Correct" is a bit of an overstatement. All Parslet errors get surfaced
    # at the beginning of the query they were in, since Parslet sees the query
    # as invalid. It would be great to have more granularity here.
    e = assert_raises(GraphQL::ParseError) do
      GraphQL.parse("
        query getCoupons {
          allCoupons: {data{id}}
        }
      ")
    end
    assert_equal('Extra input after last repetition at line 2 char 9.', e.message)
    assert_equal(2, e.line)
    assert_equal(9, e.col)
  end

  describe "merging fragments with different keys" do
    let(:query_string) { %|
      query getCheeseFieldsThroughDairy {
        ... cheeseFrag3
        dairy {
          ...flavorFragment
          ...fatContentFragment
        }
      }
      fragment flavorFragment on Dairy {
        cheese {
          flavor
        }
        milks {
          id
        }
      }
      fragment fatContentFragment on Dairy {
        cheese {
          fatContent
        }
        milks {
          fatContent
        }
      }

      fragment cheeseFrag1 on Query {
        cheese(id: 1) {
          id
        }
      }
      fragment cheeseFrag2 on Query {
        cheese(id: 1) {
          flavor
        }
      }
      fragment cheeseFrag3 on Query {
        ... cheeseFrag2
        ... cheeseFrag1
      }
    |}

    it "should include keys from each fragment" do
      expected = {"data" => {
        "dairy" => {
          "cheese" => {
            "flavor" => "Brie",
            "fatContent" => 0.19
          },
          "milks" => [
            {
              "id" => "1",
              "fatContent" => 0.04,
            }
          ],
        },
        "cheese" => {
          "id" => 1,
          "flavor" => "Brie"
        },
      }}
      assert_equal(expected, result)
    end
  end

  describe "malformed queries" do
    describe "whitespace-only" do
      let(:query_string) { " " }
      it "doesn't blow up" do
        assert_equal({}, result)
      end
    end

    describe "empty string" do
      let(:query_string) { "" }
      it "doesn't blow up" do
        assert_equal({}, result)
      end
    end
  end

  describe "field argument default values" do
    let(:query_string) {%|
      query getCheeses(
        $search: [DairyProductInput]
        $searchWithDefault: [DairyProductInput] = [{source: COW}]
      ){
        noVariable: searchDairy(product: $search) {
          ... cheeseFields
        }
        noArgument: searchDairy {
          ... cheeseFields
        }
        variableDefault: searchDairy(product: $searchWithDefault) {
          ... cheeseFields
        }

      }
      fragment cheeseFields on Cheese { flavor }
    |}

    it "has a default value" do
      default_source = schema.query.fields["searchDairy"].arguments["product"].default_value[0]["source"]
      assert_equal("SHEEP", default_source)
    end

    describe "when a variable is used, but not provided" do
      it "uses the default_value" do
        assert_equal("Manchego", result["data"]["noVariable"]["flavor"])
      end
    end

    describe "when the argument isn't passed at all" do
      it "uses the default value" do
        assert_equal("Manchego", result["data"]["noArgument"]["flavor"])
      end
    end

    describe "when the variable has a default" do
      it "uses the variable default" do
        assert_equal("Brie", result["data"]["variableDefault"]["flavor"])
      end
    end
  end

  describe "query variables" do
    let(:query_string) {%|
      query getCheese($cheeseId: Int!){
        cheese(id: $cheeseId) { flavor }
      }
    |}

    describe "when they can be coerced" do
      let(:query_variables) { {"cheeseId" => 2.0} }

      it "coerces them on the way in" do
        assert("Gouda", result["data"]["cheese"]["flavor"])
      end
    end

    describe "when they can't be coerced" do
      let(:query_variables) { {"cheeseId" => "2"} }

      it "raises an error" do
        assert_equal(result["errors"][0]["message"], %{Variable cheeseId of type Int! was provided invalid value "2"})
      end
    end

    describe "when they aren't provided" do
      let(:query_variables) { {} }

      it "raises an error" do
        expected = "Variable cheeseId of type Int! can't be null"
        assert_equal(result["errors"][0]["message"], expected)
      end
    end

    describe "default values" do
      let(:query_string) {%|
        query getCheese($cheeseId: Int = 3){
          cheese(id: $cheeseId) { id, flavor }
        }
      |}

      describe "when no value is provided" do
        let(:query_variables) { {} }

        it "uses the default" do
          assert(3, result["data"]["cheese"]["id"])
          assert("Manchego", result["data"]["cheese"]["flavor"])
        end
      end

      describe "when a value is provided" do
        it "uses the provided variable" do
          assert(2, result["data"]["cheese"]["id"])
          assert("Gouda", result["data"]["cheese"]["flavor"])
        end
      end

      describe "when complex values" do
        let(:query_variables) { {"search" => [{"source" => "COW"}]} }
        let(:query_string) {%|
          query getCheeses($search: [DairyProductInput]!){
            cow: searchDairy(product: $search) {
              ... on Cheese {
                flavor
              }
            }
          }
        |}

        it "coerces recursively" do
          assert_equal("Brie", result["data"]["cow"]["flavor"])
        end
      end
    end
  end
end
