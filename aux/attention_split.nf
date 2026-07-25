nextflow.enable.dsl = 2

params.dataset = params.dataset ?: "/mnt/beegfs/home/amolina/Fase_3/HMIL_TESIS/HistologyMultiInstanceLearningTransfer/params/class_dataset_ki_HRR.csv"
params.features_dir = params.features_dir ?: "/mnt/beegfs/home/amolina/hrr_scanner/processed_data/trident(mag_corrected)/"
params.base_results = params.base_results ?: "/mnt/beegfs/home/amolina/Fase_3/MIL_transfer_tesis/TCGA_HRR_ki/partial/results"
params.outdir = params.outdir ?: "/mnt/beegfs/home/amolina/Fase_3/MIL_transfer_tesis/TCGA_HRR_ki/partial/att"
params.combos = params.combos ?: "uni_v2.transformer,virchow2.transformer"

params.n_parts = params.n_parts ?: 2
params.max_parallel_predict = params.max_parallel_predict ?: 7


def feature_folder(String feature_extractor) {

    def root = params.features_dir
        .toString()
        .replaceFirst('/+$', '')

    if (feature_extractor == "uni_v2") {
        return "${root}/20x_256px_0px_overlap/features_uni_v2"
    }

    if (feature_extractor == "virchow2") {
        return "${root}/20x_224px_0px_overlap/features_virchow2"
    }

    throw new IllegalArgumentException(
        "Feature extractor no soportado: ${feature_extractor}"
    )
}


process split_dataset {

    tag "split_${params.n_parts}_parts"

    input:
    path dataset_csv

    output:
    path "dataset_part_*.csv", emit: parts

    script:
    """
    set -euo pipefail

    python3 - "${dataset_csv}" "${params.n_parts}" <<'PY'
import csv
import sys
from pathlib import Path

input_csv = Path(sys.argv[1])
n_parts = int(sys.argv[2])

if n_parts < 1:
    raise RuntimeError("n_parts debe ser mayor o igual a 1.")

if not input_csv.exists():
    raise RuntimeError(f"No existe el dataset: {input_csv}")

with input_csv.open("r", newline="", encoding="utf-8-sig") as handle:
    reader = csv.reader(handle)
    all_rows = list(reader)

if len(all_rows) < 2:
    raise RuntimeError(
        "El dataset debe contener una cabecera y al menos una fila."
    )

header = all_rows[0]

rows = [
    row
    for row in all_rows[1:]
    if any(str(value).strip() for value in row)
]

if len(rows) == 0:
    raise RuntimeError("El dataset no contiene filas válidas.")

parts = [
    rows[index::n_parts]
    for index in range(n_parts)
]

for part_index, part_rows in enumerate(parts, start=1):
    output_csv = Path(f"dataset_part_{part_index}.csv")

    with output_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\\n")
        writer.writerow(header)
        writer.writerows(part_rows)

    print(
        f"Parte {part_index}: "
        f"{len(part_rows)} láminas -> {output_csv}"
    )

print(f"Total de láminas: {len(rows)}")
PY
    """
}


process predict {

    tag "${feature_extractor}.${mil}:part_${part_id}"

    maxForks params.max_parallel_predict.toInteger()

    input:
    tuple(
        val(part_id),
        path(dataset_part),
        path(features_path),
        path(best_params),
        path(best_model),
        val(feature_extractor),
        val(mil)
    )

    output:
    path ".done", emit: done

    script:
    """
    set -euo pipefail

    if [ -n "\${HISTOMIL_ENV_BIN:-}" ]; then
        export PATH="\${HISTOMIL_ENV_BIN}:\$PATH"
    fi

    if [ -n "\${HISTOMIL_CODE_DIR:-}" ]; then
        export PYTHONPATH="\${HISTOMIL_CODE_DIR}:\${PYTHONPATH:-}"
    fi

    COMBO="${feature_extractor}.${mil}"

    STAGE_DIR="hmt_predict_part_${part_id}"
    FINAL_ROOT="${params.outdir}/heatmaps/\${COMBO}"
    ATT_DIR="\${FINAL_ROOT}/attention_scores"
    PRED_DIR="\${FINAL_ROOT}/predictions_by_slide"
    LOG_DIR="\${FINAL_ROOT}/logs"

    rm -rf "\${STAGE_DIR}"

    mkdir -p "\${STAGE_DIR}"
    mkdir -p "\${ATT_DIR}"
    mkdir -p "\${PRED_DIR}"
    mkdir -p "\${LOG_DIR}"

    echo "============================================================"
    echo "Proceso:     predict"
    echo "Combinación: \${COMBO}"
    echo "Parte:       ${part_id}"
    echo "CSV:         ${dataset_part}"
    echo "Láminas:     \$(( \$(wc -l < "${dataset_part}") - 1 ))"
    echo "Features:    ${features_path}"
    echo "Params:      ${best_params}"
    echo "Modelo:      ${best_model}"
    echo "Outdir:      ${params.outdir}"
    echo "Stage dir:   \${STAGE_DIR}"
    echo "ATT_DIR:     \${ATT_DIR}"
    echo "PRED_DIR:    \${PRED_DIR}"
    echo "============================================================"

    histomil-predict \\
        --csv_path "${dataset_part}" \\
        --params_path "${best_params}" \\
        --weights_path "${best_model}" \\
        --features_folder "${features_path}" \\
        --feature_extractor "${feature_extractor}" \\
        --mil "${mil}" \\
        --results_dir "\${STAGE_DIR}"

    python3 - "\${STAGE_DIR}" "\${ATT_DIR}" "${part_id}" <<'PY'
from pathlib import Path
import shutil
import sys

stage_dir = Path(sys.argv[1])
att_dir = Path(sys.argv[2])
part_id = sys.argv[3]

attention_directory = stage_dir / "attention_scores"

if not attention_directory.exists():
    print(f"No se encontró attention_scores en: {attention_directory}")
    raise SystemExit(0)

h5_files = sorted(attention_directory.rglob("*.h5"))

for source_file in h5_files:
    destination_file = att_dir / source_file.name

    if destination_file.exists():
        stem = destination_file.stem
        suffix = destination_file.suffix
        destination_file = att_dir / f"{stem}_part_{part_id}{suffix}"

    shutil.copy2(source_file, destination_file)

print(f"Attention scores copiados a outdir: {len(h5_files)}")
PY

    python3 - "\${STAGE_DIR}" "\${PRED_DIR}" "${feature_extractor}" "${mil}" "${part_id}" <<'PY'
import csv
import re
import sys
from pathlib import Path

stage_dir = Path(sys.argv[1])
pred_dir = Path(sys.argv[2])
feature_extractor = sys.argv[3]
mil = sys.argv[4]
part_id = sys.argv[5]

predictions_file = stage_dir / "predictions.csv"

if not predictions_file.exists():
    print(f"No se encontró predictions.csv en: {predictions_file}")
    raise SystemExit(0)

with predictions_file.open("r", newline="", encoding="utf-8-sig") as handle:
    reader = csv.DictReader(handle)
    fieldnames = reader.fieldnames
    rows = list(reader)

if not fieldnames:
    print("predictions.csv no contiene cabecera.")
    raise SystemExit(0)

slide_candidates = {
    "slide_id",
    "slide",
    "slide_name",
    "filename",
    "file"
}

slide_column = next(
    (
        column
        for column in fieldnames
        if column.lower() in slide_candidates
    ),
    None
)

if slide_column is None:
    output_file = pred_dir / (
        f"predictions_{feature_extractor}_{mil}_part_{part_id}.csv"
    )

    with output_file.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=fieldnames,
            lineterminator="\\n"
        )
        writer.writeheader()
        writer.writerows(rows)

    print(
        "No se detectó una columna de slide. "
        f"Se guardó una predicción agrupada: {output_file}"
    )

    raise SystemExit(0)

valid_suffixes = (
    ".tif",
    ".tiff",
    ".svs",
    ".ndpi",
    ".mrxs"
)

for row_index, row in enumerate(rows, start=1):
    slide_value = str(row.get(slide_column, "")).strip()
    slide_name = Path(slide_value).name

    slide_base = slide_name

    for suffix in valid_suffixes:
        if slide_name.lower().endswith(suffix):
            slide_base = slide_name[:-len(suffix)]
            break

    if not slide_base:
        slide_base = f"part_{part_id}_row_{row_index}"

    slide_base = re.sub(
        r"[^A-Za-z0-9._-]+",
        "_",
        slide_base
    )

    output_file = pred_dir / (
        f"predictions_{feature_extractor}_{mil}_{slide_base}.csv"
    )

    if output_file.exists():
        output_file = pred_dir / (
            f"predictions_{feature_extractor}_{mil}_{slide_base}_part_{part_id}.csv"
        )

    with output_file.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=fieldnames,
            lineterminator="\\n"
        )
        writer.writeheader()
        writer.writerow(row)

print(f"Predicciones individuales guardadas en outdir: {len(rows)}")
PY

    if [ -f "\${STAGE_DIR}/predictions.csv" ]; then
        cp "\${STAGE_DIR}/predictions.csv" \\
           "\${LOG_DIR}/predictions_part_${part_id}.csv"
    fi

    rm -rf "\${STAGE_DIR}"

    touch .done
    """
}


workflow {

    dataset_ch = Channel.fromPath(
        params.dataset,
        checkIfExists: true
    )

    split_dataset(dataset_ch)

    chunks_ch = split_dataset.out.parts
        .flatten()
        .map { chunk_file ->

            def part_id = chunk_file
                .baseName
                .tokenize("_")
                .last()
                .toInteger()

            tuple(
                part_id,
                chunk_file
            )
        }

    combo_ch = Channel
        .fromList(
            params.combos
                .toString()
                .split(",")
                .collect { it.trim() }
                .findAll { it }
        )
        .map { combo ->

            def parts = combo.tokenize(".")

            if (parts.size() != 2) {
                throw new IllegalArgumentException(
                    "Combinación inválida: ${combo}. " +
                    "Debe usar formato feature_extractor.mil"
                )
            }

            def feature_extractor = parts[0]
            def mil = parts[1]

            def features_path = file(
                feature_folder(feature_extractor),
                checkIfExists: true
            )

            def best_params = file(
                "${params.base_results}/best_params/best_params_${combo}.json",
                checkIfExists: true
            )

            def best_model = file(
                "${params.base_results}/models/${combo}/0_best_model.pt",
                checkIfExists: true
            )

            tuple(
                features_path,
                best_params,
                best_model,
                feature_extractor,
                mil
            )
        }

    prediction_jobs_ch = chunks_ch
        .combine(combo_ch)
        .map {
            part_id,
            dataset_part,
            features_path,
            best_params,
            best_model,
            feature_extractor,
            mil ->

            tuple(
                part_id,
                dataset_part,
                features_path,
                best_params,
                best_model,
                feature_extractor,
                mil
            )
        }

    predict(prediction_jobs_ch)
}