
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
        mkdir -p splits/$target_column/
        cp $dataset splits/$target_column/
        touch splits_0_bool.csv
        touch splits_1_bool.csv
        touch splits_2_bool.csv
        touch splits_3_bool.csv
        touch splits_4_bool.csv
        """
}
