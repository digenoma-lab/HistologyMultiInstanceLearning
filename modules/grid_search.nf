
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
    publishDir "${params.outdir}/training", mode:"copy"
    input:
    tuple val(feature_extractor), path(features_path), val(mil)
    tuple path(dataset), val(target_column), path(splits_dir)
    path(train_script)
    output:
    path(mil), emit: results
    script:
    """
    for FOLD in {0..10}
    do
        python -u $train_script --fold \$FOLD --feature_extractor $feature_extractor \\
        --features_path $features_path --splits_dir $splits_dir \\
        --csv_path $splits_dir/dataset.csv --mil $mil \\
        --results_dir $mil
    done
    """
    stub:
    """
    mkdir ./$mil
    for FOLD in {0..10}
    do
        touch ./$mil/\${FOLD}-checkpoint.pt
        touch ./$mil/\${FOLD}.csv
    done
    """
}