include {
    split_dataset;
    grid_search;
    concat_results;
} from '../modules/grid_search.nf'

workflow grid_search_workflow {
    take:
    dataset
    target
    configs
    main:
    split_dataset(dataset, target)
    grid_search(configs, split_dataset.out.splits)
    concat_results(grid_search.out.results.collect())
    emit:
    summary = concat_results.out.summary
    predictions = grid_search.out.predictions
    best_model_params = grid_search.out.best_model_params
}