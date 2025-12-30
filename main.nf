include {
    split_dataset
} from './modules/grid_search.nf'
workflow {
    dataset = Channel.value(file(params.dataset))
    feature_extractors = Channel.fromPath("${projectDir}/params/feature_extractors.csv")
        .splitCsv(header: true, sep: ',')
        .map { row ->
            tuple(
                row.patch_encoder,
                row.slide_encoder,
                row.patch_size,
                row.mag,
                row.batch_size,
                row.overlap
            )
        }
    feature_paths = feature_extractors.map { row ->
        tuple( row[1], file("${params.features_dir}/${row[3]}x_${row[2]}px_${row[5]}px_overlap/slide_features_${row[1]}/"))
    }
    script_split_dataset = Channel.value(file("${projectDir}/bin/make_splits.py"))

    split_dataset(dataset, params.target, script_split_dataset)
}