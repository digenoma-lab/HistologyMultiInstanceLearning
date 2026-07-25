process split_dataset {
    publishDir "${params.outdir}/splits/", mode:"copy"
    input:
        path(dataset)
        val(target_column)
    output:
        tuple path(dataset), val(target_column), path(target_column), emit: splits
    script:
        """
        if [ -n "\${histomil_env_bin:-}" ]; then
            export PYTHONPATH="\${histomil_code_dir:-}:\${PYTHONPATH:-}"
            hmt_splits="\${histomil_env_bin}/histomil-splits"
        else
            hmt_splits="histomil-splits"
        fi

        "\$hmt_splits" --csv_path $dataset --target $target_column \\
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
    publishDir "${params.outdir}/training/${feature_extractor}.${mil}", mode:"copy", pattern: "test_results_*.csv"
    publishDir "${params.outdir}/predictions/${feature_extractor}.${mil}", mode:"copy", pattern: "predictions_*.csv"
    publishDir "${params.outdir}/best_params/", mode:"copy", pattern: "best_params_*.json"
    publishDir "${params.outdir}/models/${feature_extractor}.${mil}", mode:"copy", pattern: "*best_model.pt"
    input:
        tuple val(feature_extractor), path(features_path), val(mil), val(transfer_mode), val(grid_params), val(checkpoint), val(folds)
        tuple path(dataset), val(target_column), path(splits_dir)
    output:
        path("test_results_${feature_extractor}.${mil}.csv"), emit: results
        tuple path("predictions_${feature_extractor}.${mil}_*.csv"), val(feature_extractor), val(mil), emit: predictions
        tuple path(dataset), path(features_path), path("best_params_${feature_extractor}.${mil}.json"), path("*best_model.pt"), val(feature_extractor), val(mil), emit: best_model_params
    script:
        """
        if [ -n "\${histomil_env_bin:-}" ]; then
            export PYTHONPATH="\${histomil_code_dir:-}:\${PYTHONPATH:-}"
            hmt_grid="\${histomil_env_bin}/histomil-grid"
            hmt_train="\${histomil_env_bin}/histomil-train"
        else
            hmt_grid="histomil-grid"
            hmt_train="histomil-train"
        fi

        if [ -n "${grid_params}" ] || [ "${transfer_mode}" != "scratch" ]; then
            test -f "${grid_params}" || { echo "ERROR: params not found: ${grid_params}"; exit 1; }

            extra_args="--transfer_mode ${transfer_mode}"

            if [ "${transfer_mode}" != "scratch" ]; then
                test -f "${checkpoint}" || { echo "ERROR: checkpoint not found: ${checkpoint}"; exit 1; }
                extra_args="\$extra_args --pretrained_checkpoint ${checkpoint}"
            fi

            "\$hmt_train" --folds ${folds} --features_path $features_path \
            --feature_extractor $feature_extractor --splits_dir $splits_dir --csv_path $splits_dir/dataset.csv \
            --mil $mil --results_dir ./ --params_path ${grid_params} \$extra_args
        else
            "\$hmt_grid" --folds ${folds} --features_path $features_path \
            --feature_extractor $feature_extractor --splits_dir $splits_dir --csv_path $splits_dir/dataset.csv \
            --mil $mil --results_dir ./
        fi
        """
    stub:
        """
        touch test_results_${feature_extractor}.${mil}.csv
        for i in {0..10}; do
            touch predictions_${feature_extractor}.${mil}_\${i}.csv
            touch \${i}-best_model.pt
        done
        touch best_params_${feature_extractor}.${mil}.json
        """
}

process concat_results {
    publishDir "${params.outdir}/training/", mode:"copy"
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
