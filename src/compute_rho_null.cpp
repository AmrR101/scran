#include "scran.h"
#include "run_dormqr.h"
#include <random>

static double rho_mult (double Ncells) {
    return 6/(Ncells*(Ncells*Ncells-1));
}

/*** Null distribution estimation without a design matrix. ***/

SEXP get_null_rho (SEXP cells, SEXP iters, SEXP seeds) {
    BEGIN_RCPP

    // Pulling out input values.
    const int Ncells=check_integer_scalar(cells, "number of cells");
    if (Ncells <= 1) { throw std::runtime_error("number of cells should be greater than 2"); }

    const int Niters=check_integer_scalar(iters, "number of iterations");
    if (Niters < 0) { throw std::runtime_error("number of iterations should be non-negative"); }

    Rcpp::IntegerVector Seeds(seeds);
    if (Seeds.size()!=Niters) {
        throw std::runtime_error("number of iterations and seeds should be the same"); 
    }

    // Filling rank vector.
    std::vector<int> rankings(Ncells);
    Rcpp::NumericVector output(Niters);
    const double mult=rho_mult(Ncells);

    for (int it=0; it<Niters; ++it) {
        std::iota(rankings.begin(), rankings.end(), 0);

        std::mt19937 generator(Seeds[it]);
        std::shuffle(rankings.begin(), rankings.end(), generator);

        double tmp=0;
        for (int cell=0; cell<Ncells; ++cell) {
            const double tmpdiff=rankings[cell]-cell;
            tmp+=tmpdiff*tmpdiff;
        }
        tmp*=mult;
        output[it]=1-tmp;            
    }

    return output;
    END_RCPP
}

/*** Null distribution estimation with a design matrix. ***/

SEXP get_null_rho_design(SEXP qr, SEXP qraux, SEXP iters, SEXP seeds) {
    BEGIN_RCPP
    const int Niters=check_integer_scalar(iters, "number of iterations");
    if (Niters <= 0) { throw std::runtime_error("number of iterations should be positive"); }

    Rcpp::IntegerVector Seeds(seeds);
    if (Seeds.size()!=Niters) {
        throw std::runtime_error("number of iterations and seeds should be the same"); 
    }

    // Setting up to multiply by the Q matrix.
    run_dormqr multQ(qr, qraux, 'N');
    const int Nobs=multQ.get_nobs();
    const int Ncoef=multQ.get_ncoefs();

    Rcpp::NumericVector output(Niters);
    std::deque<std::pair<double, int> > collected1(Nobs), collected2(Nobs);
    std::deque<int> rank1(Nobs), rank2(Nobs);
    const double mult=rho_mult(Nobs);

    /* Simulating residuals, using the Q-matrix to do it. We set the main effects to zero 
     * (hence, starting from "Ncoefs") and simulate normals for the residual effects.
     * We then use this to reconstruct the residuals themselves - twice - and then compute 
     * correlations between the two reconstructions.
     */
    for (int it=0; it<Niters; ++it) {
        std::mt19937 generator(Seeds[it]);
        std::normal_distribution<double> cpp_rnorm;

        for (int mode=0; mode<2; ++mode) {
            std::fill(multQ.rhs.begin(), multQ.rhs.begin()+Ncoef, 0);
            for (int col=Ncoef; col<Nobs; ++col) {
                multQ.rhs[col]=cpp_rnorm(generator);
            }

            // Computing the residuals.
            multQ.run();

            // Sorting.
            std::deque<std::pair<double, int> >& current=(mode ? collected1 : collected2);
            for (int row=0; row<Nobs; ++row) {
                current[row].first=multQ.rhs[row];
                current[row].second=row;
            }
            std::sort(current.begin(), current.end());
            std::deque<int>& rank=(mode ? rank1 : rank2);
            for (int row=0; row<Nobs; ++row) {
                rank[current[row].second]=row;
            }
        }

        // Computing the squared difference in the ranks.
        double& rho=(output[it]=0);
        for (int row=0; row<Nobs; ++row) {
            const double tmpdiff=rank1[row]-rank2[row];
            rho+=tmpdiff*tmpdiff;
        }
        rho*=mult;
        rho=1-rho;
    }

    return output;    
    END_RCPP
}

SEXP test_rnorm (SEXP N, SEXP seed) {
    std::mt19937 generator(check_integer_scalar(seed, "seed"));
    std::normal_distribution<double> cpp_rnorm;
    Rcpp::NumericVector output(check_integer_scalar(N, "number"));
    for (auto& val : output) { val = cpp_rnorm(generator); }
    return output;
}
