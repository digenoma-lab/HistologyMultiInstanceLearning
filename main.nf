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

    def fe_rows = file(params.feature_extractors).splitCsv(header: true, sep: ',')
    def fe_map = fe_rows.collectEntries { row ->
        [(row.patch_encoder): row]
    }
    def arch_list = file(params.architectures)
        .splitCsv(header: true, sep: ',')
        .collect { row -> row.architecture }
    def arch_set = arch_list as Set

    def resolveFeatureDir = { encoder, meta ->
        file("${params.features_dir}/${meta.mag}x_${meta.patch_size}px_${meta.overlap}px_overlap/features_${encoder}/")
    }
    def requireFeatureDir = { encoder, meta ->
        def features_path = resolveFeatureDir(encoder, meta)
        if (!features_path.exists()) {
            error "Feature directory not found for '${encoder}': ${features_path}"
        }
        return features_path
    }

    if (params.configs) {
        def config_rows = file(params.configs).splitCsv(header: true, sep: ',')
        config_rows.each { row ->
            if (!fe_map.containsKey(row.feature_extractor)) {
                error "Unknown feature_extractor '${row.feature_extractor}' in configs (not in ${params.feature_extractors})"
            }
            if (!arch_set.contains(row.architecture)) {
                error "Unknown architecture '${row.architecture}' in configs (not in ${params.architectures})"
            }
        }

        base_configs = Channel.fromList(
            config_rows.collect { row ->
                def meta = fe_map[row.feature_extractor]
                tuple(
                    row.feature_extractor,
                    requireFeatureDir(row.feature_extractor, meta),
                    row.architecture
                )
            }
        ).combine(folds)
    }
    else {
        feature_extractors = Channel.fromList(
            fe_rows.collect { row ->
                tuple(
                    row.patch_encoder,
                    requireFeatureDir(row.patch_encoder, row)
                )
            }
        )

        architectures = Channel.fromList(
            arch_list.collect { arch -> tuple(arch) }
        )

        base_configs = feature_extractors
            .combine(architectures)
            .combine(folds)
    }

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
    do_heatmap = Channel.value(params.heatmap)
    slides_dir = params.slides_dir
        ? Channel.fromPath(params.slides_dir)
        : Channel.empty()

    training_workflow(dataset, params.target, grid_configs, train_configs, folds)

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
        dataset,
        do_heatmap
    )
}
