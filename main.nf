include {
    grid_search_workflow;
} from './workflows/grid_search.nf'
include {
    plots;
} from './workflows/plots.nf'
include {
    heatmap_workflow;
} from './workflows/heatmap.nf'
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

    grid_search_workflow(dataset, params.target, configs)

    plots(grid_search_workflow.out.summary,
        grid_search_workflow.out.predictions,
        script_boxplot, script_roc_auc)

    heatmap_workflow(grid_search_workflow.out.summary,
        grid_search_workflow.out.best_model_params,
        slides_dir, dataset)
}