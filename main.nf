include {
    split_dataset;
    concat_results;
    boxplot_auc;
    grid_search;
    roc_auc_curve;
    predict;
    heatmap;
    convert_tiff;
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
            tuple(row.architecture)
        }
    feature_paths = feature_extractors.map { row ->
        tuple( row[0], file("${params.features_dir}/${row[2]}x_${row[1]}px_${row[3]}px_overlap/features_${row[0]}/"))
    }
    configs = feature_paths.combine(architectures)
    script_boxplot = Channel.value(file("${projectDir}/bin/boxplot_auc.R"))
    script_roc_auc = Channel.value(file("${projectDir}/bin/roc_auc_curve.R"))

    slides_dir = Channel.fromPath(params.slides_dir)
    split_dataset(dataset, params.target)
    grid_search(configs, split_dataset.out.splits)
    concat_results(grid_search.out.results.collect())
    boxplot_auc(concat_results.out.summary, script_boxplot)
    roc_auc_curve(grid_search.out.predictions, script_roc_auc)
    predict(grid_search.out.best_model_params)
    row_dataset = dataset.splitCsv(header: true, sep: ',').map { row ->
        row.slide_id
    }
    heatmap_tuple = row_dataset.combine(slides_dir)
    heatmap_tuple = heatmap_tuple.combine(predict.out.attention_scores)
    heatmap(heatmap_tuple)
    //heatmap.out.topk_patches.view()
    convert_tiff(heatmap.out.heatmap)
}