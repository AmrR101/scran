#' Model the per-gene variance
#'
#' Model the variance of the log-expression profiles for each gene, 
#' decomposing it into technical and biological components based on a fitted mean-variance trend.
#' 
#' @param x A numeric matrix of log-counts, or a \linkS4class{SingleCellExperiment} containing such a matrix.
#' @param design A numeric matrix containing blocking terms for uninteresting factors of variation.
#' @param subset.row See \code{?"\link{scran-gene-selection}"}, specifying the rows for which to model the variance.
#' Defaults to all genes in \code{x}.
#' @param subset.fit An argument similar to \code{subset.row}, specifying the rows to be used for trend fitting.
#' Defaults to \code{subset.row}.
#' @param BPPARAM A \linkS4class{BiocParallelParam} object indicating whether parallelization should be performed across genes.
#' @param ... For the generic, further arguments to pass to each method.
#' 
#' For the ANY method, further arguments to pass to \code{\link{fitTrendVar}}.
#'
#' For the \linkS4class{SingleCellExperiment} method, further arguments to pass to the ANY method.
#' @param block A factor specifying the blocking levels for each cell in \code{x}.
#' If specified, variance modelling is performed separately within each block and statistics are combined across blocks.
#' @param equiweight A logical scalar indicating whether statistics from each block should be given equal weight.
#' Otherwise, each block is weighted according to its number of cells.
#' Only used if \code{block} is specified.
#' @param method String specifying how p-values should be combined when \code{block} is specified, see \code{\link{combinePValues}}.
#' @param assay.type String or integer scalar specifying the assay containing the log-expression values.
#'
#' @details
#' For each gene, we compute the variance and mean of the log-expression values.
#' A trend is fitted to the variance against the mean for all genes using \code{\link{fitTrendVar}}.
#' The fitted value for each gene is used as a proxy for the technical component of variation for each gene,
#' under the assumption that most genes exhibit a low baseline level of variation that is not biologically interesting.
#' The biological component of variation for each gene is defined as the the residual from the trend.
#'
#' Ranking genes by the biological component enables identification of interesting genes for downstream analyses 
#' in a manner that accounts for the mean-variance relationship.
#' We use log-transformed expression values to blunt the impact of large positive outliers and to ensure that large variances are driven by strong log-fold changes between cells rather than differences in counts.
#' Log-expression values are also used in downstream analyses like PCA, so modelling them here avoids inconsistencies with different quantifications of variation across analysis steps.
#'
#' By default, the trend is fitted using all of the genes in \code{x}.
#' If \code{subset.fit} is specified, the trend is fitted using only the specified subset,
#' and the technical components for all other genes are determined by extrapolation or interpolation.
#' This could be used to perform the fit based on genes that are known to have low variance, thus weakening the assumption above.
#' Note that this does not refer to spike-in transcripts, which should be handled via \code{\link{modelGeneVarWithSpikes}}.
#'
#' @section Handling uninteresting factors:
#' Setting \code{block} will estimate the mean and variance of each gene for cells in each level of \code{block} separately.
#' The trend is fitted separately for each level, and the variance decomposition is also performed separately.
#' Per-level statistics are then combined to obtain a single value per gene:
#' \itemize{
#' \item For means and variance components, this is done by averaging values across levels.
#' If \code{equiweight=FALSE}, a weighted average is used where the value for each level is weighted by the number of cells.
#' By default, all levels are equally weighted when combining statistics.
#' \item Per-level p-values are combined using \code{\link{combinePValues}} according to \code{method}.
#' By default, Fisher's method is used to identify genes that are highly variable in any batch.
#' Whether or not this is responsive to \code{equiweight} depends on the chosen method.
#' \item Blocks with fewer than 2 cells are completely ignored and do not contribute to the combined mean, variance component or p-value.
#' }
#'
#' Use of \code{block} is the recommended approach for accounting for any uninteresting categorical factor of variation.
#' In addition to accounting for systematic differences in expression between levels of the blocking factor,
#' it also accommodates differences in the mean-variance relationships.
#'
#' Alternatively, uninteresting factors can be used to construct a design matrix to pass to the function via \code{design}.
#' In this case, a linear model is fitted to the expression profile for each gene and the residual variance is calculated.
#' This approach is useful for covariates or additive models that cannot be expressed as a one-way layout for use in \code{block}.
#' However, it assumes that the error is normally distributed with equal variance for all observations of a given gene.
#' 
#' Use of \code{block} and \code{design} together is currently not supported and will lead to an error.
#'
#' @section Computing p-values:
#' The p-value for each gene is computed by assuming that the variance estimates are normally distributed around the trend, and that the standard deviation of the variance distribution is proportional to the value of the trend.
#' This is used to construct a one-sided test for each gene based on its \code{bio}, under the null hypothesis that the biological component is equal to zero.
#' The proportionality constant for the standard deviation is set to the \code{std.dev} returned by \code{\link{fitTrendVar}}.
#' This is estimated from the spread of per-gene variance estimates around the trend, so the null hypothesis effectively becomes \dQuote{is this gene \emph{more} variable than other genes of the same abundance?}
#'
#' @return 
#' A \linkS4class{DataFrame} is returned where each row corresponds to a gene in \code{x} (or in \code{subset.row}, if specified).
#' This contains the numeric fields:
#' \describe{
#' \item{\code{mean}:}{Mean normalized log-expression per gene.}
#' \item{\code{total}:}{Variance of the normalized log-expression per gene.}
#' \item{\code{bio}:}{Biological component of the variance.}
#' \item{\code{tech}:}{Technical component of the variance.}
#' \item{\code{p.value, FDR}:}{Raw and adjusted p-values for the test against the null hypothesis that \code{bio<=0}.}
#' }
#' 
#' If \code{block} is not specified, 
#' the \code{metadata} of the DataFrame contains the output of running \code{\link{fitTrendVar}} on the specified features,
#' along with the \code{mean} and \code{var} used to fit the trend.
#'
#' If \code{block} is specified,
#' the output contains another \code{per.block} field.
#' This field is itself a DataFrame of DataFrames, where each internal DataFrame contains statistics for the variance modelling within each block and has the same format as described above. 
#' Each internal DataFrame's \code{metadata} contains the output of \code{\link{fitTrendVar}} for the cells of that block.
#'
#' @author Aaron Lun
#' 
#' @examples
#' library(scater)
#' sce <- mockSCE()
#' sce <- logNormCounts(sce)
#'
#' # Fitting to all features.
#' allf <- modelGeneVar(sce)
#' allf
#' 
#' plot(allf$mean, allf$total)
#' curve(metadata(allf)$trend(x), add=TRUE, col="dodgerblue")
#'
#' # Using a subset of features for fitting.
#' subf <- modelGeneVar(sce, subset.fit=1:100)
#' subf 
#' 
#' plot(subf$mean, subf$total)
#' curve(metadata(subf)$trend(x), add=TRUE, col="dodgerblue")
#' points(metadata(subf)$mean, metadata(subf)$var, col="red", pch=16)
#'
#' # With blocking. 
#' block <- sample(LETTERS[1:2], ncol(sce), replace=TRUE)
#' blk <- modelGeneVar(sce, block=block)
#' blk
#'
#' par(mfrow=c(1,2))
#' for (i in colnames(blk$per.block)) {
#'     current <- blk$per.block[[i]]
#'     plot(current$mean, current$total)
#'     curve(metadata(current)$trend(x), add=TRUE, col="dodgerblue")
#' }
#' 
#' @name modelGeneVar
#' @aliases modelGeneVar modelGeneVar,ANY-method modelGeneVar,SingleCellExperiment-method
#' @seealso
#' \code{\link{fitTrendVar}}, for the trend fitting options.
#' 
#' \code{\link{modelGeneVarWithSpikes}}, for modelling variance with spike-in controls.
NULL

#############################
# Defining the basic method #
#############################

#' @importFrom BiocParallel SerialParam
#' @importFrom scater .subset2index
.model_gene_var <- function(x, block=NULL, design=NULL, subset.row=NULL, subset.fit=NULL, 
    ..., equiweight=TRUE, method="fisher", BPPARAM=SerialParam()) 
{
    FUN <- function(s) {
        .compute_mean_var(x, block=block, design=design, subset.row=s, 
            block.FUN=compute_blocked_stats_none, 
            residual.FUN=compute_residual_stats_none, 
            BPPARAM=BPPARAM)
    }
    x.stats <- FUN(subset.row)

    if (is.null(subset.fit)) {
        fit.stats <- x.stats
    } else {
        # Yes, we could do this more efficiently by rolling up 'subset.fit'
        # into 'subset.row' for a single '.compute_mean_var' call... but I CBF'd.
        fit.stats <- FUN(subset.fit)
    }

    collected <- .decompose_log_exprs(x.stats$means, x.stats$vars, fit.stats$means, fit.stats$vars, 
        x.stats$ncells, ...)
    output <- .combine_blocked_statistics(collected, method, equiweight, x.stats$ncells)
    rownames(output) <- rownames(x)[.subset2index(subset.row, x)]
    output
}

#########################
# Setting up S4 methods #
#########################

#' @export
setGeneric("modelGeneVar", function(x, ...) standardGeneric("modelGeneVar"))

#' @export
#' @rdname modelGeneVar
setMethod("modelGeneVar", "ANY", .model_gene_var)

#' @export
#' @importFrom SummarizedExperiment assay
#' @rdname modelGeneVar
setMethod("modelGeneVar", "SingleCellExperiment", function(x, ..., assay.type="logcounts")
{
    .model_gene_var(x=assay(x, i=assay.type), ...)
}) 
