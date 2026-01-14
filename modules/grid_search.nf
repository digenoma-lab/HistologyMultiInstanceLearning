
process split_dataset {
    publishDir "${params.outdir}/splits/", mode:"copy"
    input:
        path(dataset)
        val(target_column)
        path(script)
    output:
        tuple path(dataset), val(target_column), path(target_column), emit: splits
    script:
        """
        python $script --csv_path $dataset --target $target_column --output_name $target_column
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
    publishDir "${params.outdir}/training/${feature_extractor}.${mil}", mode:"copy"
    input:
    tuple val(feature_extractor), path(features_path), val(mil), path(grid_params)
    tuple path(dataset), val(target_column), path(splits_dir)
    path(train_script)
    output:
    path("test_results.csv"), emit: results
    script:
    """
    python -u $train_script --folds 10 --features_path $features_path \\
    --feature_extractor $feature_extractor --splits_dir $splits_dir --csv_path $splits_dir/dataset.csv \\
    --mil $mil --results_dir ./ --grid_params $grid_params
    """
    stub:
    """
    touch test_results.csv
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
    echo "epoch,train_loss,train_auc,train_acc,val_loss,val_auc,val_acc,test_auc,test_acc,optimal_threshold,f1_macro,fold,feature_extractor,mil" > head.txt
    cat ${csv} | grep -v "epoch" > body.txt
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
