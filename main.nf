include {
    split_dataset;
    train_model
} from './modules/grid_search.nf'
workflow {
    dataset = Channel.value(file(params.dataset))
    feature_extractors = Channel.fromPath("${projectDir}/params/feature_extractors.csv")
        .splitCsv(header: true, sep: ',')
        .map { row ->
            tuple(
                row.patch_encoder,
                row.patch_size,
                row.mag,
                row.overlap
            )
        }
    architectures = Channel.fromPath("${projectDir}/params/architectures.csv")
        .splitCsv(header: true, sep: ',')
        .map { row ->
            tuple(
                row.architecture,
            )
        }
    feature_paths = feature_extractors.map { row ->
        tuple( row[0], file("${params.features_dir}/${row[2]}x_${row[1]}px_${row[3]}px_overlap/features_${row[0]}/"))
    }
    configs = feature_paths.combine(architectures)
    script_split_dataset = Channel.value(file("${projectDir}/bin/make_splits.py"))
    script_train = Channel.value(file("${projectDir}/bin/train.py"))

    split_dataset(dataset, params.target, script_split_dataset)
    train_model(configs, split_dataset.out.splits, script_train)
}