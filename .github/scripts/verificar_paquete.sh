#!/usr/bin/env sh
# Verifica el tarball que deja `mix hex.build`: que pese menos de 1 MB y que
# no arrastre lo que no es del paquete (los PLT de dialyzer; el directorio
# vacío priv/plts/ viaja porque priv/ está en :files, y no pesa; la verificación
# de prompts, los tests, los benchmarks, el CI). Lista el contenido para que
# el log lo muestre. Lo corren ci.yml (job `paquete`) y release.yml antes de
# publicar: la 0.4.0 descubrió las dos cosas al empujar el tag.
set -eu

tar="$(ls ancho_fijo-*.tar | head -1)"
bytes="$(wc -c < "$tar")"
echo "paquete: $tar, $bytes bytes"

tar -xOf "$tar" contents.tar.gz | tar -tzf - | sort > contenido_del_paquete.txt
cat contenido_del_paquete.txt

if [ "$bytes" -gt 1000000 ]; then
  echo "::error::el paquete pesa $bytes bytes, más de 1 MB: algo que no es del paquete viajó adentro"
  exit 1
fi

for patron in '^priv/plts/.' 'prompts' '^test/' '^bench/' '^\.github/' 'CONTRIBUTING'; do
  if grep -Eq "$patron" contenido_del_paquete.txt; then
    echo "::error::el paquete incluye archivos que no debería (patrón $patron); revise :files y :exclude_patterns en mix.exs"
    exit 1
  fi
done

echo "paquete verificado: $(wc -l < contenido_del_paquete.txt) archivos"
