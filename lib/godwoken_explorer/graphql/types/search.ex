defmodule GodwokenExplorer.Graphql.Types.Search do
  use Absinthe.Schema.Notation
  alias GodwokenExplorer.Graphql.Resolvers, as: Resolvers

  object :search_querys do
    @desc """
    keyword can be: udt name| account eth_address | address | transaction hash | block number
    ```graphql
    query {
      search_keyword(input: { keyword: "UDT"}){
        type
        id
      }
    }
    ```
    """
    field :search_keyword, :search_result do
      arg(:input, non_null(:search_keyword_input))
      resolve(&Resolvers.Search.search_keyword/3)
    end

    @desc """
    ```graphql
    search_udt example:
    query {
      search_udt(input: { fuzzy_name: "%ERC%", limit: 1 }) {
        entries {
          id
          name
          symbol
          type
          contract_address_hash
        }
        metadata {
          total_count
          before
          after
        }
      }
    }
    ```
    ```json
    {
      "data": {
        "search_udt": {
          "entries": [
            {
              "contract_address_hash": "0x8e82245c50864754654d2fae31367444e10b990e",
              "id": 89001,
              "name": "testERC20",
              "symbol": "testERC20",
              "type": "NATIVE"
            }
          ],
          "metadata": {
            "after": "g3QAAAABaAJkAARkZXNjZAACaWRiAAFbqQ==",
            "before": null,
            "total_count": 715
          }
        }
      }
    }
    ```
    """
    field :search_udt, :paginate_search_udts do
      arg(:input, non_null(:search_udt_input), default_value: %{})
      resolve(&Resolvers.Search.search_udt/3)
    end

    @desc """
    query {
      search_bit_alias(
        input: {
          bit_alias: "freder.bit"
        }
      )
    }

    {
      "data": {
        "search_bit_alias": "0xcc0af0af911dd40853b8c8dfee90b32f8d1ecad6"
      }
    }
    """

    field :search_bit_alias, :string do
      arg(:input, non_null(:search_bit_alias_input))
      resolve(&Resolvers.Search.search_bit_alias/3)
    end

    field :batch_fetch_addresses_by_aliases, list_of(:address_bit_alias) do
      arg(:input, non_null(:batch_fetch_addresses_by_alias_input))
      resolve(&Resolvers.Search.batch_fetch_addresses_by_aliases/3)
    end

    field :batch_fetch_aliases_by_addresses, list_of(:address_bit_alias) do
      arg(:input, non_null(:batch_fetch_aliases_by_addresses_input))
      resolve(&Resolvers.Search.batch_fetch_aliases_by_addresses/3)
    end
  end

  object :address_bit_alias do
    field(:address, :hash_address)
    field(:bit_alias, :string)
  end

  object :search_result do
    field(:type, :search_type)
    field(:id, :string)
  end

  object :paginate_search_udts do
    field(:entries, list_of(:search_udt_result))
    field(:metadata, :paginate_metadata)
  end

  object :search_udt_result do
    field(:id, :integer, description: "UDT primary key")
    field(:contract_address_hash, :hash_address, description: "The udt contract address.")
    field(:icon, :string, description: "UDT icon url.")

    field :name, :string do
      description(
        "For bridge token, read from [UAN](https://github.com/nervosnetwork/rfcs/pull/335);For native token, read from contract."
      )

      resolve(&Resolvers.UDT.name/3)
    end

    field :symbol, :string do
      description(
        "For bridge token, read from [UAN](https://github.com/nervosnetwork/rfcs/pull/335);For native token, read from contract."
      )

      resolve(&Resolvers.UDT.symbol/3)
    end

    field(:type, :udt_type, description: " Bridge means from layer1;Native means layer2 contract.")

    field(:eth_type, :eth_type, description: "EVM token type.")
  end

  enum :search_type do
    value(:address)
    value(:block)
    value(:transaction)
    value(:udt)
    value(:account)
  end

  input_object :search_bit_alias_input do
    field(:bit_alias, non_null(:string))
  end

  input_object :batch_fetch_addresses_by_alias_input do
    field(:bit_aliases, non_null(list_of(:string)))
  end

  input_object :batch_fetch_aliases_by_addresses_input do
    field(:addresses, non_null(list_of(:hash_address)))
  end

  input_object :search_keyword_input do
    field(:keyword, non_null(:string))
  end

  input_object :search_udt_input do
    field(:fuzzy_name, :string)
    field(:contract_address, :hash_address)
    import_fields(:paginate_input)
  end
end
