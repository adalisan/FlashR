% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/FlashR.R
\docType{methods}
\name{matrix}
\alias{as.matrix,fm-method}
\alias{as.matrix,fmV-method}
\alias{fm.as.matrix}
\alias{fm.is.matrix}
\alias{fm.matrix}
\alias{matrix}
\title{Matrices}
\usage{
\S4method{as.matrix}{fm}(x)

\S4method{as.matrix}{fmV}(x)

fm.is.matrix(fm)

fm.as.matrix(x)

fm.matrix(vec, nrow, ncol, byrow = FALSE)
}
\arguments{
\item{x}{an R object}

\item{vec}{an R data vector.}

\item{nrow}{the desired number of rows.}

\item{ncol}{the desired number of columns.}

\item{byrow}{logical. If \code{FALSE} (the default) the matrix is filled by
columns, otherwise the matrix is filled by rows.}
}
\description{
\code{fm.matrix} creates a matrix from the given set of values.
\code{as.matrix} attempts to turn a FlashR matrix to an R matrix.
\code{fm.as.matrix} attempts to turn its argument into a FlashR matrix.
\code{fm.is.matrix} indicates whether a FlashR object is a matrix.
}
\details{
Currently, \code{fm.matrix} takes an R vector or a FlashR vector as input
and the length of the vector must be the same as the number of rows if
\code{byrow} is \code{FALSE} or the same as the number of columns if
\code{byrow} is \code{TRUE}.
}
\examples{
mat <- fm.matrix(runif(100), 100, 2)
mat <- as.matrix(fm.runif.matrix(100, 2))
mat <- fm.as.matrix(matrix(runif(200), 100, 2))
res <- fm.is.matrix(mat)
}

