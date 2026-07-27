include {
    split_dataset;
    grid_search;
    train;
    concat_results;
} from '../modules/grid_search.nf'

workflow training_workflow {
    take:
    dataset
    target
    grid_configs
    train_configs

    main:
    split_dataset(dataset, target)

    grid_search(grid_configs, split_dataset.out.splits)
    train(train_configs, split_dataset.out.splits)

    results = grid_search.out.results.mix(train.out.results)
    predictions = grid_search.out.predictions.mix(train.out.predictions)
    best_model_params = grid_search.out.best_model_params.mix(train.out.best_model_params)

    concat_results(results.collect())

    emit:
    summary = concat_results.out.summary
    predictions = predictions
    best_model_params = best_model_params
}
