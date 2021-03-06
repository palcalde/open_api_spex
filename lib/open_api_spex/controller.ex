defmodule OpenApiSpex.Controller do
  @moduledoc ~S'''
  Generation of OpenAPI documentation via ExDoc documentation and tags.

  ## Supported OpenAPI fields

  ### `description` and `summary`

  Description of endpoint will be filled with documentation string in the same
  manner as ExDocs, so first line will be used as a `summary` and whole
  documentation will be used as `description` field.

  ### `operation_id`
  The action's `operation_id` can be set explicitly using a `@doc` tag.
  If no `operation_id` is specified, it will default to the action's module path: `Module.Name.function_name`

  ### `parameters`

  Parameters of the endpoint are defined by `:parameters` tag which should be
  map or keyword list that is formed as:

  ```
  [
    param_name: definition
  ]
  ```

  Where `definition` is `OpenApiSpex.Parameter.t()` structure or map or keyword
  list that accepts the same arguments.

  ### `responses`

  Responses are controlled by `:responses` tag. Responses must be defined as
  a map or keyword list in form of:

  ```
  %{
    200 => {"Response name", "application/json", schema},
    :not_found => {"Response name", "application/json", schema}
  }
  ```

  Where atoms are the same as `Plug.Conn.Status.code/1` values.

  ### `requestBody`

  Controlled by `:request_body` parameter and is defined as a tuple in form
  `{description, mime, schema}` or `{description, mime, schema, opts}` that
  matches the arguments of `OpenApiSpex.Operation.request_body/3` or
  `OpenApiSpex.Operation.request_body/4`, respectively.

  ```
  @doc request_body: {
    "CartUpdateRequest",
    "application/vnd.api+json",
    CartUpdateRequest,
    required: true
  }
  ```

  ### `tags`

  Tags are controlled by `:tags` attribute. In contrast to other attributes, this
  one will also inherit all tags defined as a module documentation attributes.

  ## Example

  ```
  defmodule UserController do
    @moduledoc tags: ["Users"]

    use MyAppWeb, :controller
    use #{inspect(__MODULE__)}

    @doc """
    Endpoint summary

    Endpoint description...
    """
    @doc parameters: [
           id: [in: :path, type: :string, required: true]
         ],
         request_body: {"Request body to update User", "application/json", UserUpdateBody, required: true},
         responses: [
           ok: {"User document", "application/json", UserSchema},
           {302, "Redirect", "text/html", EmptyResponse, headers: %{"Location" => %Header{description: "Redirect Location"}}}
         ]
    def update(conn, %{id: id}) do
      user_params = conn.body_params
      # …
    end
  end
  ```
  '''

  alias OpenApiSpex.{Operation, Response}

  defmacro __using__(_opts) do
    quote do
      @doc false
      @spec open_api_operation(atom()) :: OpenApiSpex.Operation.t()
      def open_api_operation(name),
        do: unquote(__MODULE__).__api_operation__(__MODULE__, name)

      defoverridable open_api_operation: 1
    end
  end

  @doc false
  @spec __api_operation__(module(), atom()) :: Operation.t() | nil
  def __api_operation__(mod, name) do
    with {:ok, {mod_meta, summary, docs, meta}} <- get_docs(mod, name) do
      %Operation{
        description: docs,
        operationId: build_operation_id(meta, mod, name),
        parameters: build_parameters(meta),
        requestBody: build_request_body(meta),
        responses: build_responses(meta),
        summary: summary,
        tags: Map.get(mod_meta, :tags, []) ++ Map.get(meta, :tags, [])
      }
    else
      _ -> nil
    end
  end

  defp get_docs(module, name) do
    {:docs_v1, _anno, _lang, _format, _module_doc, mod_meta, mod_docs} = Code.fetch_docs(module)

    doc_for_function =
      Enum.find(mod_docs, fn
        {{:function, ^name, _}, _, _, _, _} -> true
        _ -> false
      end)

    if doc_for_function do
      {_, _, _, docs, meta} = doc_for_function
      docs = Map.get(docs, "en", "")
      [summary | _] = String.split(docs, ~r/\n\s*\n/, parts: 2)

      {:ok, {mod_meta, summary, docs, meta}}
    else
      IO.warn("No docs found for function #{module}.#{name}/2")
      nil
    end
  end

  defp build_operation_id(meta, mod, name) do
    Map.get(meta, :operation_id, "#{inspect(mod)}.#{name}")
  end

  defp build_parameters(%{parameters: params}) do
    for {name, options} <- params do
      {location, options} = Keyword.pop(options, :in, :query)
      {type, options} = Keyword.pop(options, :type, :string)
      {description, options} = Keyword.pop(options, :description, "")

      Operation.parameter(name, location, type, description, options)
    end
  end

  defp build_parameters(_), do: []

  defp build_responses(%{responses: responses}) do
    Map.new(responses, fn
      {status, {description, mime, schema}} ->
        {Plug.Conn.Status.code(status), Operation.response(description, mime, schema)}

      {status, {description, mime, schema, opts}} ->
        {Plug.Conn.Status.code(status), Operation.response(description, mime, schema, opts)}

      {status, %Response{} = response} ->
        {Plug.Conn.Status.code(status), response}
    end)
  end

  defp build_responses(_), do: []

  defp build_request_body(%{body: {name, mime, schema}}) do
    IO.warn("Using :body key for requestBody is deprecated. Please use :request_body instead.")
    Operation.request_body(name, mime, schema)
  end

  defp build_request_body(%{request_body: {name, mime, schema}}) do
    Operation.request_body(name, mime, schema)
  end

  defp build_request_body(%{request_body: {name, mime, schema, opts}}) do
    Operation.request_body(name, mime, schema, opts)
  end

  defp build_request_body(_), do: nil
end
