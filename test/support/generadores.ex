defmodule AnchoFijo.Generadores do
  @moduledoc false
  # Genera layouts junto con un registro válido y su línea serializada. La
  # serialización vive acá y no en la librería a propósito: 0.1 solo lee.

  use ExUnitProperties

  @doc false
  # Devuelve %{layout: t, linea: binario, registro: mapa, campos: [spec]}.
  def layout_con_registro(opts \\ []) do
    maximo = Keyword.get(opts, :campos, 6)

    gen all(especificaciones <- list_of(campo(), min_length: 1, max_length: maximo)) do
      especificaciones =
        especificaciones
        |> Enum.with_index(1)
        |> Enum.map(fn {especificacion, indice} -> nombrar(especificacion, indice) end)

      layout =
        AnchoFijo.Layout.nuevo!(campos: Enum.map(especificaciones, & &1.definicion))

      %{
        layout: layout,
        campos: especificaciones,
        linea: Enum.map_join(especificaciones, & &1.texto),
        registro:
          especificaciones
          |> Enum.reject(&(&1.tipo == :relleno))
          |> Map.new(&{&1.definicion[:nombre], &1.esperado})
      }
    end
  end

  defp campo do
    one_of([
      texto(),
      entero(),
      decimal(),
      decimal_con_moneda(),
      fecha(),
      hora(),
      fecha_hora(),
      rut(),
      constante(),
      relleno()
    ])
  end

  # Un literal del formato: va al registro con su valor declarado.
  defp constante do
    gen all(
          largo <- integer(1..8),
          valor <- string(:alphanumeric, min_length: 1, max_length: largo)
        ) do
      %{
        definicion: [largo: largo, tipo: :constante, valor: valor],
        tipo: :constante,
        esperado: valor,
        texto: String.pad_trailing(valor, largo)
      }
    end
  end

  # Un filler: en la línea, su carácter repetido; en el registro, nada.
  defp relleno do
    gen all(largo <- integer(1..8), caracter <- member_of([" ", "0", "*"])) do
      %{
        definicion: [largo: largo, tipo: :relleno, relleno: caracter],
        tipo: :relleno,
        esperado: nil,
        texto: String.duplicate(caracter, largo)
      }
    end
  end

  @doc false
  # Un RUT válido con todas las presentaciones que llegan en archivos reales.
  # Devuelve %{cuerpo: entero, canonico: "12345678-5", representaciones: [..]}.
  def rut_valido do
    gen all(cuerpo <- integer(1..99_999_999)) do
      dv = AnchoFijo.Rut.digito_verificador(cuerpo)
      digitos = Integer.to_string(cuerpo)

      %{
        cuerpo: cuerpo,
        dv: dv,
        canonico: digitos <> "-" <> dv,
        representaciones: [
          digitos <> "-" <> dv,
          digitos <> dv,
          digitos <> "-" <> String.downcase(dv),
          con_puntos(digitos) <> "-" <> dv,
          String.pad_leading(digitos <> dv, 12, "0")
        ]
      }
    end
  end

  defp rut do
    gen all(
          %{canonico: canonico, representaciones: representaciones} <- rut_valido(),
          texto <- member_of(representaciones)
        ) do
      %{
        definicion: [largo: byte_size(texto), tipo: :rut],
        tipo: :rut,
        esperado: canonico,
        texto: texto
      }
    end
  end

  defp con_puntos(digitos) do
    digitos
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(".", &Enum.join/1)
    |> String.reverse()
  end

  defp texto do
    gen all(
          largo <- integer(1..12),
          contenido <- string(:alphanumeric, max_length: largo)
        ) do
      %{
        definicion: [largo: largo],
        tipo: :texto,
        esperado: contenido,
        texto: String.pad_trailing(contenido, largo)
      }
    end
  end

  defp entero do
    gen all(
          largo <- integer(1..9),
          {signo, magnitud, texto} <- numero_con_signo(largo)
        ) do
      %{
        definicion: [largo: largo, tipo: :entero, signo: signo],
        tipo: :entero,
        esperado: magnitud,
        texto: texto
      }
    end
  end

  defp decimal do
    gen all(
          largo <- integer(1..12),
          precision <- integer(0..min(4, largo)),
          {signo, unidades, texto} <- numero_con_signo(largo)
        ) do
      %{
        definicion: [largo: largo, tipo: :decimal, precision: precision, signo: signo],
        tipo: :decimal,
        esperado: {unidades, precision},
        texto: texto
      }
    end
  end

  # Con `moneda:` la precisión la pone la tabla ISO 4217 y el valor es un
  # `AnchoFijo.Monto`; el texto es el mismo que sin moneda, porque los
  # decimales son implícitos.
  defp decimal_con_moneda do
    gen all(
          moneda <- member_of([:clp, :usd, :eur, :jpy, :kwd, :bhd]),
          {:ok, precision} = AnchoFijo.Monto.escala(moneda),
          largo <- integer(max(1, precision)..12),
          {signo, unidades, texto} <- numero_con_signo(largo)
        ) do
      %{
        definicion: [largo: largo, tipo: :decimal, moneda: moneda, signo: signo],
        tipo: :decimal,
        esperado: AnchoFijo.Monto.nuevo(unidades, moneda),
        texto: texto
      }
    end
  end

  # Un número que cabe en `largo`, con el signo donde el layout lo declare.
  # Con un solo dígito de ancho no hay lugar para el signo: siempre positivo.
  # Los formatos de mainframe escriben el positivo con un espacio al final, y
  # eso también se genera, porque es lo que el trim tiene que absorber.
  defp numero_con_signo(1) do
    gen all(valor <- integer(0..9)) do
      {:inicial, valor, Integer.to_string(valor)}
    end
  end

  defp numero_con_signo(largo) do
    gen all(
          signo <- member_of([:inicial, :final]),
          negativo? <- boolean(),
          magnitud <- integer(0..(Integer.pow(10, largo - 1) - 1))
        ) do
      digitos = String.pad_leading(Integer.to_string(magnitud), largo - 1, "0")
      valor = if negativo?, do: -magnitud, else: magnitud

      texto =
        case {signo, negativo?} do
          {:inicial, true} -> "-" <> digitos
          {:inicial, false} -> "0" <> digitos
          {:final, true} -> digitos <> "-"
          {:final, false} -> digitos <> " "
        end

      {signo, valor, texto}
    end
  end

  # Los formatos con año de cuatro dígitos leen cualquier fecha; los de dos
  # solo la ventana del pivote (2000-2099 por default), así que para esos la
  # fecha se genera adentro de la ventana.
  defp fecha do
    gen all(
          formato <-
            member_of([
              :aaaammdd,
              :ddmmaaaa,
              :mmddaaaa,
              :aammdd,
              :ddmmaa,
              :mmddaa,
              :aaaaddd,
              :aaddd,
              "DD/MM/AAAA",
              "AAAA-MM-DD"
            ]),
          dias <- integer(0..36_500)
        ) do
      inicio = if dos_digitos?(formato), do: ~D[2000-01-01], else: ~D[1950-01-01]
      fecha = Date.add(inicio, dias)
      texto = serializar(fecha, formato)

      %{
        definicion: [largo: String.length(texto), tipo: :fecha, formato: formato],
        tipo: :fecha,
        esperado: fecha,
        texto: texto
      }
    end
  end

  defp hora do
    gen all(
          formato <- member_of([:hhmmss, :hhmm, "HH:MM:SS"]),
          segundos <- integer(0..86_399)
        ) do
      hora = Time.add(~T[00:00:00], segundos, :second)
      hora = if formato == :hhmm, do: %{hora | second: 0}, else: hora
      texto = serializar(hora, formato)

      %{
        definicion: [largo: String.length(texto), tipo: :hora, formato: formato],
        tipo: :hora,
        esperado: hora,
        texto: texto
      }
    end
  end

  defp fecha_hora do
    gen all(
          formato <-
            member_of([:aaaammddhhmmss, :aaaammddhhmm, :ddmmaaaahhmmss, "AAAA-MM-DD HH:MM:SS"]),
          dias <- integer(0..36_500),
          segundos <- integer(0..86_399)
        ) do
      valor =
        NaiveDateTime.new!(
          Date.add(~D[1950-01-01], dias),
          Time.add(~T[00:00:00], segundos, :second)
        )

      valor = if formato == :aaaammddhhmm, do: %{valor | second: 0}, else: valor
      texto = serializar(valor, formato)

      %{
        definicion: [largo: String.length(texto), tipo: :fecha_hora, formato: formato],
        tipo: :fecha_hora,
        esperado: valor,
        texto: texto
      }
    end
  end

  defp dos_digitos?(formato), do: formato in [:aammdd, :ddmmaa, :mmddaa, :aaddd]

  # La serialización de los generadores es independiente de la librería a
  # propósito: Calendar.strftime es el oráculo.
  @strftime %{
    :aaaammdd => "%Y%m%d",
    :ddmmaaaa => "%d%m%Y",
    :mmddaaaa => "%m%d%Y",
    :aammdd => "%y%m%d",
    :ddmmaa => "%d%m%y",
    :mmddaa => "%m%d%y",
    :aaaaddd => "%Y%j",
    :aaddd => "%y%j",
    "DD/MM/AAAA" => "%d/%m/%Y",
    "AAAA-MM-DD" => "%Y-%m-%d",
    :hhmmss => "%H%M%S",
    :hhmm => "%H%M",
    "HH:MM:SS" => "%H:%M:%S",
    :aaaammddhhmmss => "%Y%m%d%H%M%S",
    :aaaammddhhmm => "%Y%m%d%H%M",
    :ddmmaaaahhmmss => "%d%m%Y%H%M%S",
    "AAAA-MM-DD HH:MM:SS" => "%Y-%m-%d %H:%M:%S"
  }

  defp serializar(valor, formato), do: Calendar.strftime(valor, Map.fetch!(@strftime, formato))

  defp nombrar(especificacion, indice) do
    nombre = :"campo_#{indice}"
    %{especificacion | definicion: [{:nombre, nombre} | especificacion.definicion]}
  end
end
