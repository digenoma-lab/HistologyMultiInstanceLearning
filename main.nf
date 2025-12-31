include {
    split_dataset;
    train_model;
    concat_results;
    boxplot_auc
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
    folds = channel.of(0..9)
    configs = feature_paths.combine(architectures).combine(folds)
    script_split_dataset = Channel.value(file("${projectDir}/bin/make_splits.py"))
    script_boxplot = Channel.value(file("${projectDir}/bin/boxplot_auc.R"))
    script_train = Channel.value(file("${projectDir}/bin/train.py"))

    split_dataset(dataset, params.target, script_split_dataset)
    train_model(configs, split_dataset.out.splits, script_train)
    concat_results(train_model.out.results.collect())
    boxplot_auc(concat_results.out.summary, script_boxplot)
}