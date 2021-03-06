#ifndef __R_UTILS_H__
#define __R_UTILS_H__

/*
 * Copyright 2014 Open Connectome Project (http://openconnecto.me)
 * Written by Da Zheng (zhengda1936@gmail.com)
 *
 * This file is part of FlashR.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <memory>

#include<Rcpp.h>

bool R_is_real(SEXP v);
bool R_is_integer(SEXP v);
bool R_is_logical(SEXP v);
bool R_is_null(SEXP v);
bool R_is_string(SEXP v);
bool R_is_list(SEXP v);
bool R_is_vector(SEXP v);

enum R_type
{
	R_LOGICAL,
	R_INT,
	R_REAL,
	R_NTYPES,
};

static inline R_type get_common_Rtype(R_type left, R_type right)
{
	// For the order we list the R types, we should cast types
	// to the one with a larger value.
	return (R_type) std::max((int) left, (int) right);
}

static inline R_type R_get_type(SEXP v)
{
	if (R_is_real(v))
		return R_type::R_REAL;
	else if (R_is_integer(v))
		return R_type::R_INT;
	else if (R_is_logical(v))
		return R_type::R_LOGICAL;
	else {
		fprintf(stderr, "The R object has unknown type\n");
		return R_type::R_NTYPES;
	}
}

size_t get_nrows(SEXP o);
size_t get_ncols(SEXP o);
size_t get_length(SEXP o);

template<class T>
bool R_get_number(SEXP v, T &ret) {
	if (R_is_real(v)) {
		ret = REAL(v)[0];
		return true;
	}
	else if (R_is_integer(v)) {
		ret = INTEGER(v)[0];
		return true;
	}
	else if (R_is_logical(v)) {
		ret = LOGICAL(v)[0];
		return true;
	}
	else
		return false;
}

/*
 * Test if this is a sparse matrix.
 */
static inline bool is_sparse(const Rcpp::S4 &matrix)
{
	std::string type = matrix.slot("type");
	return type == "sparse";
}

static inline bool is_vector(const Rcpp::S4 &vec)
{
	return vec.is("fmV");
}

static inline bool is_factor_vector(const Rcpp::S4 &vec)
{
	return vec.is("fmVFactor");
}

void R_gc();
SEXP R_create_s4fm(SEXP fm);

#endif
