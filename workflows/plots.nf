include {
    boxplot_auc;
    roc_auc_curve;
} from '../modules/plots.nf'
workflow plots {
    take:
    summary
    predictions
    script_boxplot
    script_roc_auc
    main:
    boxplot_auc(summary, script_boxplot)
    roc_auc_curve(predictions, script_roc_auc)
    emit:
    boxplot_auc = boxplot_auc.out.plot
    roc_auc_curve = roc_auc_curve.out.plot
}