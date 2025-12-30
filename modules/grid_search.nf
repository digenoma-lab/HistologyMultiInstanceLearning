
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

process train_model {
    publishDir "${params.outdir}/training/${feature_extractor}.${mil}", mode:"copy"
    input:
    tuple val(feature_extractor), path(features_path), val(mil), val(fold)
    tuple path(dataset), val(target_column), path(splits_dir)
    path(train_script)
    output:
    path("${feature_extractor}.${mil}.${fold}.csv"), emit: results
    path("${feature_extractor}.${mil}.${fold}-checkpoint.pt"), emit: checkpoint
    script:
    """
    python -u $train_script --fold $fold --feature_extractor $feature_extractor \\
    --features_path $features_path --splits_dir $splits_dir \\
    --csv_path $splits_dir/dataset.csv --mil $mil \\
    --results_dir ./
    """
    stub:
    """
    touch ${feature_extractor}.${mil}.${fold}-checkpoint.pt
    touch ${feature_extractor}.${mil}.${fold}.csv
    """
}

process concat_results {
    input:
    path(csv)
    output:
    path("summary.csv"), emit: summary
    script:
    """
    echo "epoch,train_loss,train_auc,train_acc,val_loss,val_auc,val_acc,test_auc,test_acc,optimal_threshold,f1_macro,fold,feature_extractor,mil" > head.txt
    cat head.txt ${csv} | grep -v "epoch" > summary.csv
    """
    stub:
    """
    touch summary.csv
    """
}