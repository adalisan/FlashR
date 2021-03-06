# Copyright 2016 Open Connectome Project (http://openconnecto.me)
# Written by Da Zheng (zhengda1936@gmail.com)
#
# This file is part of FlashR.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#' KMeans clustering
#'
#' Perform k-means clustering on a data matrix.
#'
#' @param data the input data matrix where each row is a data point.
#' @param centers either the number of clusters, say k, or a set of
#'		  initial (distinct) cluster centers. If a number, a random set
#'		  of (distinct) rows in `x' is chosen as the initial centers.
#' @param algorithm character. Currently, we only support "Lloyd".
#' @param iter.max the maximal number of iterations.
#' @param debug This indicates whether to print debug info.
#' @param use.blas a logical value indicating whether to use BLAS to
#'                 compute Euclidean distance.
#' @return a vector that contains cluster Ids for each data point.
#' @author Da Zheng <dzheng5@@jhu.edu>
fm.kmeans <- function(data, centers, iter.max=10, algorithm=c("Lloyd"),
					  debug=FALSE, use.blas=FALSE)
{
	n <- dim(data)[1]
	m <- dim(data)[2]
	agg.sum <- fm.create.agg.op(fm.bo.add, fm.bo.add, "sum")
	agg.which.min <- fm.create.agg.op(fm.bo.which.min, NULL, "which.min")
	# We need to convert the layout because argmin over all rows requires
	# to convert the matrix layout. Converting layout every iteration
	# is expensive.
	data <- fm.materialize(fm.conv.layout(data, byrow=TRUE))

	cal.centers <- function(data, parts) {
		centers1 <- fm.groupby(data, 2, parts, agg.sum)
		centers1 <- as.matrix(centers1)
		cnts <- as.data.frame(fm.table(parts))
		centers.idx <- as.vector(cnts$val) + 1
		# Some centers may not have been initialized if no data points
		# are assigned to them. I need to reset those data centers.
		centers <- matrix(rep.int(0, length(centers1)), dim(centers1)[1],
						  dim(centers1)[2])
		centers[centers.idx,] <- centers1[centers.idx,]
		# Calculate the mean for each cluster, which is the cluster center
		# for the next iteration.
		sizes <- rep.int(1, dim(centers)[1])
		sizes[centers.idx] <- as.vector(cnts$Freq)
		centers <- diag(1/sizes) %*% centers
		fm.as.matrix(centers)
	}

	# If `centers' is a scalar, we randomly choose some data points from
	# the data matrix as initial centers.
	if (length(centers) == 1) {
		num.centers <- centers
		rand.k <- runif(num.centers, 1, nrow(data))
		new.centers <- data[rand.k,]
	}
	else {
		num.centers <- nrow(centers)
		new.centers <- fm.conv.R2FM(centers)
	}
	parts <- NULL

	iter <- 0
	start.time <- Sys.time()
	num.moves <- nrow(data)
	if (use.blas)
		rsData2 <- rowSums(data * data)
	while (num.moves > 0 && iter < iter.max) {
		if (debug)
			iter.start <- Sys.time()
		centers <- new.centers
		old.parts <- parts
		gc()

		if (use.blas) {
			rsCenters2 <- rowSums(centers * centers)
			m <- -2 * data %*% t(centers)
			m <- m + rsData2
			m <- sweep(m, 2, rsCenters2, "+")
		}
		else
			m <- fm.inner.prod(data, t(centers), fm.bo.euclidean, fm.bo.add)

		parts <- as.integer(fm.agg.mat(m, 1, agg.which.min) - 1)
		# Have the vector materialized during the computation.
		fm.set.cached(parts, TRUE, TRUE)

		new.centers <- cal.centers(data, fm.as.factor(parts, num.centers))
		if (!is.null(old.parts))
			num.moves <- as.vector(sum(as.numeric(old.parts != parts)))
		iter <- iter + 1
		if (debug) {
			iter.end <- Sys.time()
			cat("iteration", iter, "takes",
				as.numeric(iter.end) - as.numeric(iter.start),
				"seconds and moves", num.moves, "data points\n")
		}
		old.parts <- NULL
		gc()
	}
	end.time <- Sys.time()
	cat("KMeans takes", iter , "iterations and",
		as.numeric(end.time) - as.numeric(start.time), "seconds\n")

	# This is what we really need, but we can't write the computation
	# in the following form yet.
	#ss <- function(x) sum(scale(x, scale = FALSE)^2)
	#withinss <- sapply(split(as.data.frame(x), cluster), ss)
	cluster <- fm.as.factor(parts, num.centers)
	cnts <- fm.table(cluster)
	x2.gsum <- fm.groupby(data * data, 2, cluster, "+")
	x.gsum <- fm.groupby(data, 2, cluster, "+")
	withinss <- as.vector(rowSums(x2.gsum - (x.gsum^2)/cnts@Freq))

	ss <- function(x) sum(scale(x, scale = FALSE)^2)
	betweenss <- as.vector(ss(new.centers[parts + 1,]))
	tot.withinss <- sum(withinss)
	totss <- tot.withinss + betweenss

	structure(list(cluster=parts+1, centers=new.centers, totss=totss, withinss=withinss,
		 tot.withinss=tot.withinss, betweenss=betweenss,
		 size=as.vector(cnts@Freq), iter=iter), class = "kmeans")
}

BIC.kmeans <- function(object, ...)
{
	m <- ncol(object$centers)
	n <- length(object$cluster)
	k <- nrow(object$centers)
	D <- object$tot.withinss
	-2 * D + log(n)*m*k
}

AIC.kmeans <- function(object, ..., k=2)
{
	m <- ncol(object$centers)
	n <- length(object$cluster)
	k <- nrow(object$centers)
	D <- object$tot.withinss
	-2 * D + 2*m*k
}
