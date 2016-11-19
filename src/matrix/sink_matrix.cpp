/*
 * Copyright 2016 Open Connectome Project (http://openconnecto.me)
 * Written by Da Zheng (zhengda1936@gmail.com)
 *
 * This file is part of FlashMatrix.
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

#include "io_interface.h"

#include "sink_matrix.h"
#include "local_matrix_store.h"
#include "EM_object.h"
#include "dense_matrix.h"
#include "materialize.h"
#include "mem_matrix_store.h"

namespace fm
{

namespace detail
{

namespace
{

class lmaterialize_col_matrix_store: public lvirtual_col_matrix_store
{
	std::vector<local_matrix_store::const_ptr> parts;
public:
	lmaterialize_col_matrix_store(
			const std::vector<local_matrix_store::const_ptr> &parts): lvirtual_col_matrix_store(
				parts[0]->get_global_start_row(), parts[0]->get_global_start_col(),
				parts[0]->get_num_rows(), parts[0]->get_num_cols(),
				parts[0]->get_type(), parts[0]->get_node_id()) {
		this->parts = parts;
	}

	virtual bool resize(off_t local_start_row, off_t local_start_col,
			size_t local_num_rows, size_t local_num_cols) {
		for (size_t i = 0; i < parts.size(); i++)
			const_cast<local_matrix_store &>(*parts[i]).resize(local_start_row,
					local_start_col, local_num_rows, local_num_cols);
		return local_matrix_store::resize(local_start_row, local_start_col,
				local_num_rows, local_num_cols);
	}
	virtual void reset_size() {
		for (size_t i = 0; i < parts.size(); i++)
			const_cast<local_matrix_store &>(*parts[i]).reset_size();
		local_matrix_store::reset_size();
	}

	using lvirtual_col_matrix_store::get_raw_arr;
	virtual const char *get_raw_arr() const {
		assert(0);
		return NULL;
	}

	using lvirtual_col_matrix_store::transpose;
	virtual matrix_store::const_ptr transpose() const {
		assert(0);
		return matrix_store::const_ptr();
	}

	using lvirtual_col_matrix_store::get_col;
	virtual const char *get_col(size_t col) const {
		assert(0);
		return NULL;
	}

	virtual local_matrix_store::const_ptr get_portion(
			size_t local_start_row, size_t local_start_col, size_t num_rows,
			size_t num_cols) const {
		assert(0);
		return local_matrix_store::const_ptr();
	}

	virtual void materialize_self() const {
		for (size_t i = 0; i < parts.size(); i++)
			parts[i]->materialize_self();
	}
};

class lmaterialize_row_matrix_store: public lvirtual_row_matrix_store
{
	std::vector<local_matrix_store::const_ptr> parts;
public:
	lmaterialize_row_matrix_store(
			const std::vector<local_matrix_store::const_ptr> &parts): lvirtual_row_matrix_store(
				parts[0]->get_global_start_row(), parts[0]->get_global_start_col(),
				parts[0]->get_num_rows(), parts[0]->get_num_cols(),
				parts[0]->get_type(), parts[0]->get_node_id()) {
		this->parts = parts;
	}

	virtual bool resize(off_t local_start_row, off_t local_start_col,
			size_t local_num_rows, size_t local_num_cols) {
		for (size_t i = 0; i < parts.size(); i++)
			const_cast<local_matrix_store &>(*parts[i]).resize(local_start_row,
					local_start_col, local_num_rows, local_num_cols);
		return local_matrix_store::resize(local_start_row, local_start_col,
				local_num_rows, local_num_cols);
	}
	virtual void reset_size() {
		for (size_t i = 0; i < parts.size(); i++)
			const_cast<local_matrix_store &>(*parts[i]).reset_size();
		local_matrix_store::reset_size();
	}

	using lvirtual_row_matrix_store::get_raw_arr;
	virtual const char *get_raw_arr() const {
		assert(0);
		return NULL;
	}

	using lvirtual_row_matrix_store::transpose;
	virtual matrix_store::const_ptr transpose() const {
		assert(0);
		return matrix_store::const_ptr();
	}

	using lvirtual_row_matrix_store::get_row;
	virtual const char *get_row(size_t row) const {
		assert(0);
		return NULL;
	}

	virtual local_matrix_store::const_ptr get_portion(
			size_t local_start_row, size_t local_start_col, size_t num_rows,
			size_t num_cols) const {
		assert(0);
		return local_matrix_store::const_ptr();
	}

	virtual void materialize_self() const {
		for (size_t i = 0; i < parts.size(); i++)
			parts[i]->materialize_self();
	}
};

/*
 * This class is used internally for materializing a group of blocks
 * that share the same underlying matrices. Once an object of the class
 * is created, we'll pass it to __mapply_portion. Thus, we only need to
 * implement a subset of its methods.
 */
class block_group: public virtual_matrix_store, public EM_object
{
	typedef std::vector<detail::matrix_store::const_ptr> store_vec_t;
	store_vec_t stores;
	const EM_object *obj;
public:
	block_group(const store_vec_t &stores): virtual_matrix_store(
			stores[0]->get_num_rows(), stores[0]->get_num_cols(),
			stores[0]->is_in_mem(), stores[0]->get_type()) {
		this->stores = stores;
		obj = dynamic_cast<const EM_object *>(stores[0].get());
		assert(obj);
	}

	/*
	 * These methods don't need to be implemented.
	 */

	virtual void materialize_self() const {
		assert(0);
	}

	virtual matrix_store::const_ptr materialize(bool in_mem,
		int num_nodes) const {
		assert(0);
		return matrix_store::const_ptr();
	}

	virtual matrix_store::const_ptr get_cols(const std::vector<off_t> &idxs) const {
		assert(0);
		return matrix_store::const_ptr();
	}
	virtual matrix_store::const_ptr get_rows(const std::vector<off_t> &idxs) const {
		assert(0);
		return matrix_store::const_ptr();
	}

	virtual matrix_store::const_ptr transpose() const {
		assert(0);
		return matrix_store::const_ptr();
	}

	/*
	 * These methods only indicate the information of the matrix.
	 */

	virtual int get_portion_node_id(size_t id) const {
		return stores[0]->get_portion_node_id(id);
	}

	virtual std::pair<size_t, size_t> get_portion_size() const {
		return stores[0]->get_portion_size();
	}

	virtual int get_num_nodes() const {
		return stores[0]->get_num_nodes();
	}

	virtual matrix_layout_t store_layout() const {
		return stores[0]->store_layout();
	}

	virtual std::string get_name() const {
		return stores[0]->get_name();
	}

	virtual std::unordered_map<size_t, size_t> get_underlying_mats() const {
		return stores[0]->get_underlying_mats();
	}

	virtual std::vector<safs::io_interface::ptr> create_ios() const {
		return obj->create_ios();
	}

	/*
	 * These are the main methods that we need to take care of.
	 */

	using virtual_matrix_store::get_portion;
	virtual local_matrix_store::const_ptr get_portion(size_t start_row,
			size_t start_col, size_t num_rows, size_t num_cols) const;
	virtual local_matrix_store::const_ptr get_portion(size_t id) const;
	using virtual_matrix_store::get_portion_async;
	virtual async_cres_t get_portion_async(
			size_t start_row, size_t start_col, size_t num_rows,
			size_t num_cols, std::shared_ptr<portion_compute> compute) const;
};

local_matrix_store::const_ptr create_local_store(matrix_layout_t store_layout,
		const std::vector<local_matrix_store::const_ptr> &portions)
{
	if (store_layout == matrix_layout_t::L_ROW)
		return local_matrix_store::const_ptr(
				new lmaterialize_row_matrix_store(portions));
	else
		return local_matrix_store::const_ptr(
				new lmaterialize_col_matrix_store(portions));
}

local_matrix_store::const_ptr block_group::get_portion(size_t start_row,
		size_t start_col, size_t num_rows, size_t num_cols) const
{
	std::vector<local_matrix_store::const_ptr> portions(stores.size());
	for (size_t i = 0; i < stores.size(); i++)
		portions[i] = stores[i]->get_portion(start_row, start_col,
				num_rows, num_cols);
	return create_local_store(store_layout(), portions);
}

local_matrix_store::const_ptr block_group::get_portion(size_t id) const
{
	std::vector<local_matrix_store::const_ptr> portions(stores.size());
	for (size_t i = 0; i < stores.size(); i++)
		portions[i] = stores[i]->get_portion(id);
	return create_local_store(store_layout(), portions);
}

/*
 * When a portion is read from diks, this portion compute is invoked.
 * It will be invoked multiple times. We need to make sure user's portion
 * compute is invoked only once.
 */
class collect_portion_compute: public portion_compute
{
	size_t num_expected;
	size_t num_reads;
	portion_compute::ptr orig_compute;
public:
	collect_portion_compute(portion_compute::ptr orig_compute,
			size_t num_expected) {
		this->num_expected = num_expected;
		this->num_reads = 0;
		this->orig_compute = orig_compute;
	}

	virtual void run(char *buf, size_t size) {
		num_reads++;
		if (num_reads == num_expected) {
			orig_compute->run(NULL, 0);
			// This only runs once.
			// Let's remove all user's portion compute to indicate that it has
			// been invoked.
			orig_compute = NULL;
		}
	}
};

async_cres_t block_group::get_portion_async(size_t start_row, size_t start_col,
		size_t num_rows, size_t num_cols, portion_compute::ptr compute) const
{
	std::vector<local_matrix_store::const_ptr> portions(stores.size());
	bool avail = false;
	portion_compute::ptr collect_compute(
			new collect_portion_compute(compute, stores.size()));
	for (size_t i = 0; i < stores.size(); i++) {
		auto ret = stores[i]->get_portion_async(start_row, start_col,
				num_rows, num_cols, collect_compute);
		portions[i] = ret.second;
		// These portions are all from the same underlying matrices, they
		// should all be available or unavailable at the same time.
		if (i == 0)
			avail = ret.first;
		else
			assert(avail == ret.first);
	}
	return async_cres_t(avail, create_local_store(store_layout(), portions));
}

}

static size_t get_num_rows(const std::vector<sink_store::const_ptr> &stores,
		size_t num_block_rows, size_t num_block_cols)
{
	size_t num_rows = 0;
	for (size_t i = 0; i < num_block_rows; i++)
		num_rows += stores[i * num_block_cols]->get_num_rows();
	return num_rows;
}

static size_t get_num_cols(const std::vector<sink_store::const_ptr> &stores,
		size_t num_block_rows, size_t num_block_cols)
{
	size_t num_cols = 0;
	for (size_t i = 0; i < num_block_cols; i++)
		num_cols += stores[i]->get_num_cols();
	return num_cols;
}

block_sink_store::ptr block_sink_store::create(
		const std::vector<matrix_store::const_ptr> &stores,
		size_t num_block_rows, size_t num_block_cols)
{
	std::vector<sink_store::const_ptr> sink_stores(stores.size());
	for (size_t i = 0; i < stores.size(); i++) {
		sink_stores[i] = std::dynamic_pointer_cast<const sink_store>(stores[i]);
		// The input matrices have to be sink matrices.
		assert(sink_stores[i]);
	}
	return block_sink_store::ptr(new block_sink_store(sink_stores,
				num_block_rows, num_block_cols));
}

block_sink_store::block_sink_store(
		// I assume all matrices are kept in row-major order.
		const std::vector<sink_store::const_ptr> &stores,
		size_t num_block_rows, size_t num_block_cols): sink_store(
			detail::get_num_rows(stores, num_block_rows,
				num_block_cols), detail::get_num_cols(stores, num_block_rows,
				num_block_cols), stores[0]->is_in_mem(), stores[0]->get_type())
{
	this->num_block_rows = num_block_rows;
	this->num_block_cols = num_block_cols;
	this->stores = stores;

	// all matrices in the block row should have the same number of rows.
	for (size_t i = 0; i < num_block_rows; i++) {
		size_t num_rows = stores[num_block_cols * i]->get_num_rows();
		for (size_t j = 0; j < num_block_cols; j++)
			assert(stores[num_block_cols * i + j]->get_num_rows() == num_rows);
	}
	// all matrices in the block row should have the same number of rows.
	for (size_t i = 0; i < num_block_cols; i++) {
		size_t num_cols = stores[i]->get_num_cols();
		for (size_t j = 0; j < num_block_rows; j++)
			assert(stores[num_block_cols * j + i]->get_num_cols() == num_cols);
	}
	assert(num_block_rows * num_block_cols == stores.size());
}

matrix_store::const_ptr block_sink_store::transpose() const
{
	assert(0);
	return matrix_store::const_ptr();
}

std::string block_sink_store::get_name() const
{
	assert(0);
	return std::string();
}

std::unordered_map<size_t, size_t> block_sink_store::get_underlying_mats() const
{
	assert(0);
	return std::unordered_map<size_t, size_t>();
}

bool block_sink_store::has_materialized() const
{
	for (size_t i = 0; i < stores.size(); i++)
		if (!stores[i]->has_materialized())
			return false;
	return true;
}

matrix_store::const_ptr block_sink_store::get_result() const
{
	if (result == NULL)
		materialize_self();
	return result;
}

std::vector<virtual_matrix_store::const_ptr> block_sink_store::get_compute_matrices() const
{
	std::vector<virtual_matrix_store::const_ptr> ret;
	for (size_t i = 0; i < stores.size(); i++) {
		auto tmp = stores[i]->get_compute_matrices();
		ret.insert(ret.end(), tmp.begin(), tmp.end());
	}
	return ret;
}

void block_sink_store::materialize_self() const
{
	if (result)
		return;

	std::vector<dense_matrix::ptr> mats(stores.size());
	for (size_t i = 0; i < stores.size(); i++)
		mats[i] = dense_matrix::create(stores[i]);
	// We don't want to materialize all block matrices together because it
	// might consume a lot of memory.
	bool ret =fm::materialize(mats, false);
	assert(ret);
	std::vector<matrix_store::const_ptr> res_stores(stores.size());
	for (size_t i = 0; i < stores.size(); i++)
		res_stores[i] = mats[i]->get_raw_store();

	mem_matrix_store::ptr res = mem_matrix_store::create(get_num_rows(),
			get_num_cols(), store_layout(), get_type(), -1);
	off_t start_row = 0;
	for (size_t i = 0; i < num_block_rows; i++) {
		off_t start_col = 0;
		for (size_t j = 0; j < num_block_cols; j++) {
			size_t block_idx = i * num_block_cols + j;
			local_matrix_store::const_ptr tmp_portion
				= res_stores[block_idx]->get_portion(0);
			assert(tmp_portion->get_num_rows()
					== res_stores[block_idx]->get_num_rows());
			assert(tmp_portion->get_num_cols()
					== res_stores[block_idx]->get_num_cols());

			local_matrix_store::ptr res_portion = res->get_portion(start_row,
					start_col, res_stores[block_idx]->get_num_rows(),
					res_stores[block_idx]->get_num_cols());
			res_portion->copy_from(*tmp_portion);
			start_col += res_stores[block_idx]->get_num_cols();
		}
		start_row += get_mat(i, 0).get_num_rows();
	}
	const_cast<block_sink_store *>(this)->result = res;
}

matrix_store::const_ptr block_sink_store::materialize(bool in_mem,
		int num_nodes) const
{
	materialize_self();
	return result;
}

}

}
