process split_dataset {
    publishDir "${params.outdir}/splits/", mode: "copy"
    input:
        path(dataset)
        val(target_column)
    output:
        tuple path(dataset), val(target_column), path(target_column), emit: splits
    script:
        """
        histomil-splits --csv_path $dataset --target $target_column \\
        --output_name $target_column --splits_dir ./
        """
    stub:
        """
        mkdir -p $target_column/
        cp $dataset $target_column/
        for i in {0..9}; do
            touch $target_column/splits_\${i}_bool.csv
            touch $target_column/splits_\${i}_descriptor.csv
        done
        """
}

process grid_search {
    tag "${feature_extractor}.${mil}"
    publishDir "${params.outdir}/training/${feature_extractor}.${mil}", mode: "copy", pattern: "test_results_*.csv"
    publishDir "${params.outdir}/predictions/${feature_extractor}.${mil}", mode: "copy", pattern: "predictions_*.csv"
    publishDir "${params.outdir}/best_params/", mode: "copy", pattern: "best_params_*.json"
    publishDir "${params.outdir}/models/${feature_extractor}.${mil}", mode: "copy", pattern: "*best_model.pt"
    input:
        tuple val(feature_extractor), path(features_path), val(mil), val(folds)
        tuple path(dataset), val(target_column), path(splits_dir)
    output:
        path("test_results_${feature_extractor}.${mil}.csv"), emit: results
        tuple path("predictions_${feature_extractor}.${mil}_*.csv"), val(feature_extractor), val(mil), emit: predictions
        tuple path(dataset), path(features_path), path("best_params_${feature_extractor}.${mil}.json"), path("*best_model.pt"), val(feature_extractor), val(mil), emit: best_model_params
    script:
        """
        histomil-grid --folds ${folds} --features_path $features_path \\
        --feature_extractor $feature_extractor --splits_dir $splits_dir --csv_path $splits_dir/dataset.csv \\
        --mil $mil --results_dir ./
        """
    stub:
        """
        touch test_results_${feature_extractor}.${mil}.csv
        for i in \$(seq 0 \$((${folds} - 1))); do
            touch predictions_${feature_extractor}.${mil}_\${i}.csv
            touch \${i}_best_model.pt
        done
        touch best_params_${feature_extractor}.${mil}.json
        """
}

process train {
    tag "${feature_extractor}.${mil}"
    publishDir "${params.outdir}/training/${feature_extractor}.${mil}", mode: "copy", pattern: "test_results_*.csv"
    publishDir "${params.outdir}/predictions/${feature_extractor}.${mil}", mode: "copy", pattern: "predictions_*.csv"
    publishDir "${params.outdir}/best_params/", mode: "copy", pattern: "best_params_*.json"
    publishDir "${params.outdir}/models/${feature_extractor}.${mil}", mode: "copy", pattern: "*best_model.pt"
    input:
        tuple val(feature_extractor),
            path(features_path),
            val(mil),
            val(folds),
            val(transfer_mode),
            val(checkpoint_results_dir),
            val(checkpoint_fold),
            val(best_params_dir)
        tuple path(dataset), val(target_column), path(splits_dir)
    output:
        path("test_results_${feature_extractor}.${mil}.csv"), emit: results
        tuple path("predictions_${feature_extractor}.${mil}_*.csv"), val(feature_extractor), val(mil), emit: predictions
        tuple path(dataset), path(features_path), path("best_params_${feature_extractor}.${mil}.json"), path("*best_model.pt"), val(feature_extractor), val(mil), emit: best_model_params
    script:
        def params_json = best_params_dir \
            ? "${best_params_dir}/best_params_${feature_extractor}.${mil}.json" \
            : "${checkpoint_results_dir}/best_params/best_params_${feature_extractor}.${mil}.json"
        def checkpoint = "${checkpoint_results_dir}/models/${feature_extractor}.${mil}/${checkpoint_fold}_best_model.pt"
        def checkpoint_arg = transfer_mode != 'scratch' \
            ? "--pretrained_checkpoint ${checkpoint}" \
            : ""
        """
        set -euo pipefail
        test -f "${params_json}" || { echo "ERROR: params not found: ${params_json}"; exit 1; }
        if [ "${transfer_mode}" != "scratch" ]; then
            test -f "${checkpoint}" || { echo "ERROR: checkpoint not found: ${checkpoint}"; exit 1; }
        fi

        histomil-train --folds ${folds} --features_path $features_path \\
        --feature_extractor $feature_extractor --splits_dir $splits_dir --csv_path $splits_dir/dataset.csv \\
        --mil $mil --results_dir ./ --params_path ${params_json} \\
        --transfer_mode ${transfer_mode} ${checkpoint_arg}
        """
    stub:
        """
        touch test_results_${feature_extractor}.${mil}.csv
        for i in \$(seq 0 \$((${folds} - 1))); do
            touch predictions_${feature_extractor}.${mil}_\${i}.csv
            touch \${i}_best_model.pt
        done
        touch best_params_${feature_extractor}.${mil}.json
        """
}

process concat_results {
    publishDir "${params.outdir}/training/", mode: "copy"
    input:
        path(csv)
    output:
        path("summary.csv"), emit: summary
    script:
        """
        head -n 1 ${csv[0]} > head.txt
        cat ${csv} | grep -v "test_auc" > body.txt
        cat head.txt body.txt > summary.csv
        """
    stub:
        """
        touch summary.csv
        """
}
