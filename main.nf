include {
    training_workflow;
} from './workflows/training.nf'
include {
    plots;
} from './workflows/plots.nf'
include {
    heatmap_workflow;
} from './workflows/heatmap.nf'

workflow {
    if (!(params.mode in ['grid', 'train'])) {
        error "params.mode must be 'grid' or 'train' (got: ${params.mode})"
    }

    dataset = Channel.value(file(params.dataset))
    folds = Channel.value(params.folds)

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
        tuple(
            row[0],
            file("${params.features_dir}/${row[2]}x_${row[1]}px_${row[3]}px_overlap/features_${row[0]}/")
        )
    }

    base_configs = feature_paths
        .combine(architectures)
        .combine(folds)

    if (params.mode == 'grid') {
        grid_configs = base_configs
        train_configs = Channel.empty()
    }
    else {
        if (params.transfer_mode != 'scratch' && !params.checkpoint_results_dir) {
            error "params.checkpoint_results_dir is required when mode=train and transfer_mode=${params.transfer_mode}"
        }
        def resolved_best_params_dir = params.best_params_dir ?: params.grid_params_dir
        if (!resolved_best_params_dir && !params.checkpoint_results_dir) {
            error "params.best_params_dir (or checkpoint_results_dir) is required when mode=train"
        }

        grid_configs = Channel.empty()
        train_configs = base_configs
            .combine(Channel.value(params.transfer_mode))
            .combine(Channel.value(params.checkpoint_results_dir))
            .combine(Channel.value(params.checkpoint_fold))
            .combine(Channel.value(resolved_best_params_dir))
    }

    script_boxplot = Channel.value(file("${projectDir}/bin/boxplot_auc.R"))
    script_roc_auc = Channel.value(file("${projectDir}/bin/roc_auc_curve.R"))
    slides_dir = Channel.fromPath(params.slides_dir)

    training_workflow(dataset, params.target, grid_configs, train_configs)

    plots(
        training_workflow.out.summary,
        training_workflow.out.predictions,
        script_boxplot,
        script_roc_auc
    )

    heatmap_workflow(
        training_workflow.out.summary,
        training_workflow.out.best_model_params,
        slides_dir,
        dataset
    )
}
