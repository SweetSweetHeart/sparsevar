% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/plotMatrix.R
\name{plotComparisonVAR}
\alias{plotComparisonVAR}
\title{Plot VAR models for comparison}
\usage{
plotComparisonVAR(var1, var2)
}
\arguments{
\item{var1}{the list containing the first VAR model matrices to be plotted}

\item{var2}{the list containing the second VAR model matrices to be plotted}
}
\value{
An \code{image} plot with a particular color palette (black zero entries, red 
for the negative ones and green for the positive)
}
\description{
Plot all the matrices of a two VAR models
}

