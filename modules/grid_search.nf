
process split_dataset {
    publishDir "${params.outdir}/splits/", mode:"copy"
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
    publishDir "${params.outdir}/training/${feature_extractor}.${mil}", mode:"copy", pattern: "test_results_*.csv"
    publishDir "${params.outdir}/predictions/${feature_extractor}.${mil}", mode:"copy", pattern: "predictions_*.csv"
    publishDir "${params.outdir}/best_params/", mode:"copy", pattern: "best_params_*.json"
    input:
    tuple val(feature_extractor), path(features_path), val(mil)
    tuple path(dataset), val(target_column), path(splits_dir)
    output:
    path("test_results_${feature_extractor}.${mil}.csv"), emit: results
    tuple path("predictions_${feature_extractor}.${mil}_*.csv"), val(feature_extractor), val(mil), emit: predictions
    path("best_params_${feature_extractor}.${mil}.json"), emit: best_params
    script:
    """
    histomil-grid --folds 10 --features_path $features_path \\
    --feature_extractor $feature_extractor --splits_dir $splits_dir --csv_path $splits_dir/dataset.csv \\
    --mil $mil --results_dir ./
    """
    stub:
    """
    touch test_results_${feature_extractor}.${mil}.csv
    for i in {0..10}; do
        touch predictions_${feature_extractor}.${mil}_\${i}.csv
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
process boxplot_auc {
    publishDir "${params.outdir}/plots/", mode:"copy"
    input:
    path(summary_file)
    path(script_boxplot)
    output:
    path("boxplot.png"), emit: plot
    script:
    """
    Rscript $script_boxplot
    """
    stub:
    """
    touch boxplot.png
    """
}

process roc_auc_curve {
    publishDir "${params.outdir}/plots/", mode:"copy"
    input:
    tuple path(predictions_files), val(feature_extractor), val(mil)
    path(script_roc_auc)
    output:
    path("${feature_extractor}.${mil}.roc_auc.png"), emit: plot
    script:
    """
    Rscript $script_roc_auc $predictions_files ${feature_extractor}.${mil}.roc_auc.png
    """
    stub:
    """
    touch ${feature_extractor}.${mil}.roc_auc.png
    """
}