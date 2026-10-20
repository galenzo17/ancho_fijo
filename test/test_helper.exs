ExUnit.start()

# En Elixir 1.14 una dependencia opcional no arranca sola con la aplicación;
# los tests de telemetría necesitan la tabla de handlers viva.
{:ok, _} = Application.ensure_all_started(:telemetry)
