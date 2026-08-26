# rotaperfume/tests_unit/test_conferencia_lib.py
"""Testes rapidos do modulo puro de conferencia -- sem rede, sem Databricks.

Este arquivo mora em rotaperfume/tests_unit/, IRMAO de rotaperfume/tests/,
de proposito: o pytest so carrega conftest.py dos diretorios no caminho
entre o rootdir e o arquivo de teste coletado. Como tests/conftest.py nao
esta nesse caminho quando voce roda 'pytest tests_unit/', o hook
pytest_configure que abre uma DatabricksSession real nunca dispara aqui.
"""
import csv

from raw.conferencia_lib import ARQUIVOS_ESPERADOS, caminho_arquivo, conferir_arquivos


def _escrever_csv(caminho, linhas_de_dado: int) -> None:
    caminho.parent.mkdir(parents=True, exist_ok=True)
    with caminho.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["coluna_a", "coluna_b"])
        for i in range(linhas_de_dado):
            writer.writerow([i, f"valor_{i}"])


def _montar_10_arquivos_ok(tmp_path):
    for sistema, nomes in ARQUIVOS_ESPERADOS.items():
        for nome in nomes:
            _escrever_csv(tmp_path / sistema / f"{nome}.csv", linhas_de_dado=5)
    return tmp_path


def test_caminho_arquivo_monta_path_esperado():
    assert (
        caminho_arquivo("/Volumes/cat/bronze/raw", "erp", "produtos")
        == "/Volumes/cat/bronze/raw/erp/produtos.csv"
    )


def test_conferir_arquivos_10_ok_sem_faltando_sem_vazio(tmp_path):
    base_dir = _montar_10_arquivos_ok(tmp_path)

    resultados, faltando, vazios = conferir_arquivos(str(base_dir), ARQUIVOS_ESPERADOS)

    assert len(resultados) == 10
    assert faltando == []
    assert vazios == []
    produtos = next(r for r in resultados if r["arquivo"] == "produtos.csv")
    assert produtos["sistema"] == "erp"
    assert produtos["linhas"] == 5
    assert produtos["bytes"] > 0


def test_conferir_arquivos_detecta_arquivo_faltando(tmp_path):
    base_dir = _montar_10_arquivos_ok(tmp_path)
    (base_dir / "erp" / "pagamentos.csv").unlink()

    resultados, faltando, vazios = conferir_arquivos(str(base_dir), ARQUIVOS_ESPERADOS)

    assert len(resultados) == 9
    assert faltando == [caminho_arquivo(str(base_dir), "erp", "pagamentos")]
    assert vazios == []


def test_conferir_arquivos_detecta_arquivo_vazio(tmp_path):
    base_dir = _montar_10_arquivos_ok(tmp_path)
    _escrever_csv(base_dir / "crm" / "clientes.csv", linhas_de_dado=0)  # so cabecalho

    resultados, faltando, vazios = conferir_arquivos(str(base_dir), ARQUIVOS_ESPERADOS)

    assert faltando == []
    assert vazios == [caminho_arquivo(str(base_dir), "crm", "clientes")]
    clientes = next(r for r in resultados if r["arquivo"] == "clientes.csv")
    assert clientes["linhas"] == 0


def test_conferir_arquivos_e_reprodutivel_apos_faltar_e_restaurar(tmp_path):
    """Prova local (sem workspace) do mesmo ciclo que a Tarefa 8 faz de verdade:
    remover um arquivo quebra a conferencia, devolver o arquivo conserta."""
    base_dir = _montar_10_arquivos_ok(tmp_path)
    alvo = base_dir / "crm" / "visitas.csv"

    alvo.unlink()
    _, faltando_apos_remover, _ = conferir_arquivos(str(base_dir), ARQUIVOS_ESPERADOS)
    assert faltando_apos_remover == [caminho_arquivo(str(base_dir), "crm", "visitas")]

    _escrever_csv(alvo, linhas_de_dado=3)
    resultados_apos_restaurar, faltando_apos_restaurar, vazios_apos_restaurar = conferir_arquivos(
        str(base_dir), ARQUIVOS_ESPERADOS
    )
    assert faltando_apos_restaurar == []
    assert vazios_apos_restaurar == []
    assert len(resultados_apos_restaurar) == 10
