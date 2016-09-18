/*
 * Copyright 2014 Open Connectome Project (http://openconnecto.me)
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

#include <boost/format.hpp>

#include "log.h"

#include "matrix_config.h"
#include "data_frame.h"
#include "bulk_operate.h"
#include "mem_vec_store.h"
#include "EM_vector.h"
#include "mem_vv_store.h"
#include "vector_vector.h"
#include "EM_vv_store.h"
#include "bulk_operate_ext.h"

namespace fm
{

data_frame::data_frame(const std::vector<named_vec_t> &named_vecs)
{
	assert(!named_vecs.empty());
	this->named_vecs = named_vecs;
	bool in_mem = named_vecs.front().second->is_in_mem();
	for (auto it = named_vecs.begin(); it != named_vecs.end(); it++) {
		assert(in_mem == it->second->is_in_mem());
		vec_map.insert(*it);
	}
}

data_frame::const_ptr data_frame::shuffle_vecs(
		const std::vector<off_t> &vec_idxs) const
{
	std::vector<named_vec_t> sub_vecs(vec_idxs.size());
	for (size_t i = 0; i < sub_vecs.size(); i++) {
		size_t idx = vec_idxs[i];
		if (idx >= get_num_vecs()) {
			BOOST_LOG_TRIVIAL(error) << "vec idx is out of bound";
			return data_frame::const_ptr();
		}
		sub_vecs[i] = named_vecs[idx];
	}
	return data_frame::create(sub_vecs);
}

bool data_frame::append(std::vector<data_frame::ptr>::const_iterator begin,
		std::vector<data_frame::ptr>::const_iterator end)
{
	std::unordered_map<std::string, std::vector<detail::vec_store::const_ptr> > vecs;
	for (size_t i = 0; i < named_vecs.size(); i++) {
		std::vector<detail::vec_store::const_ptr> _vecs;
		_vecs.push_back(get_vec(named_vecs[i].first));
		vecs.insert(std::pair<std::string, std::vector<detail::vec_store::const_ptr> >(
					named_vecs[i].first, _vecs));
	}

	for (auto it = begin; it != end; it++) {
		data_frame::ptr df = *it;
		if (df->get_num_vecs() != get_num_vecs()) {
			BOOST_LOG_TRIVIAL(error)
				<< "The data frames have different numbers of vectors";
			return false;
		}
		for (auto vec_it = vecs.begin(); vec_it != vecs.end(); vec_it++) {
			detail::vec_store::const_ptr vec = df->get_vec(vec_it->first);
			if (vec == NULL) {
				BOOST_LOG_TRIVIAL(error)
					<< "The data frames have different names on the vectors";
				return false;
			}
			if (vec->get_type() != vec_it->second.front()->get_type()) {
				BOOST_LOG_TRIVIAL(error)
					<< "The data frames have different types for the vectors with the same name";
				return false;
			}
			vec_it->second.push_back(vec);
		}
	}

	for (auto it = vecs.begin(); it != vecs.end(); it++) {
		detail::vec_store::ptr vec = get_vec(it->first);
		vec->append(it->second.begin() + 1, it->second.end());
	}
	return true;
}

bool data_frame::append(data_frame::ptr df)
{
	for (auto it = named_vecs.begin(); it != named_vecs.end(); it++) {
		if (df->get_vec(it->first) == NULL) {
			BOOST_LOG_TRIVIAL(error)
				<< boost::format("The new data frame doesn't have column %1%")
				% it->first;
			return false;
		}
	}

	for (auto it = named_vecs.begin(); it != named_vecs.end(); it++)
		it->second->append(*df->get_vec(it->first));
	return true;
}

data_frame::const_ptr data_frame::sort(const std::string &col_name) const
{
	detail::vec_store::const_ptr sorted_col = get_vec(col_name);
	if (sorted_col == NULL) {
		BOOST_LOG_TRIVIAL(error) << boost::format(
				"The column %1% doesn't exist") % col_name;
		return data_frame::const_ptr();
	}
	if (sorted_col->is_sorted())
		return this->shallow_copy();

	data_frame::ptr ret(new data_frame());
	if (sorted_col->is_in_mem()) {
		detail::vec_store::ptr copy_col = sorted_col->deep_copy();
		detail::smp_vec_store::ptr idxs = detail::smp_vec_store::cast(
				copy_col->sort_with_index());
		for (size_t i = 0; i < get_num_vecs(); i++) {
			detail::smp_vec_store::const_ptr mem_vec
				= detail::smp_vec_store::cast(get_vec(i));
			if (mem_vec == sorted_col) {
				ret->add_vec(col_name, copy_col);
			}
			else {
				detail::mem_vec_store::ptr tmp = mem_vec->get(*idxs);
				ret->add_vec(get_vec_name(i), tmp);
			}
		}
	}
	else {
		std::vector<std::string> names;
		std::vector<detail::EM_vec_store::const_ptr> vecs;
		names.push_back(col_name);
		vecs.push_back(detail::EM_vec_store::cast(sorted_col));
		for (size_t i = 0; i < named_vecs.size(); i++) {
			if (named_vecs[i].second != sorted_col) {
				vecs.push_back(detail::EM_vec_store::cast(named_vecs[i].second));
				names.push_back(named_vecs[i].first);
			}
		}
		std::vector<detail::EM_vec_store::ptr> sorted = detail::sort(vecs);
		// We should reshuffle the columns so that the columns in the returned
		// data frame have the same order as the current data frame.
		size_t j = 1;
		for (size_t i = 0; i < named_vecs.size(); i++) {
			if (named_vecs[i].first == col_name)
				ret->add_vec(col_name, sorted[0]);
			else {
				assert(names[j] == named_vecs[i].first);
				ret->add_vec(names[j], sorted[j]);
				j++;
			}
		}
	}
	return ret;
}

bool data_frame::is_sorted(const std::string &col_name) const
{
	return get_vec_ref(col_name).is_sorted();
}

data_frame::const_ptr data_frame::shallow_copy() const
{
	return data_frame::const_ptr(new data_frame(*this));
}

bool data_frame::add_vec(const std::string &name, detail::vec_store::ptr vec)
{
	if (get_num_vecs() > 0) {
		if (vec->get_length() != get_num_entries()) {
			BOOST_LOG_TRIVIAL(error)
				<< "Add a vector with different number of entries from the data frame";
			return false;
		}
		if (vec->is_in_mem() != named_vecs.front().second->is_in_mem()) {
			BOOST_LOG_TRIVIAL(error)
				<< "Add a vector in different storage from the data frame.";
			return false;
		}
	}
	named_vecs.push_back(named_vec_t(name, vec));
	vec_map.insert(named_vec_t(name, vec));
	return true;
}

data_frame::ptr merge_data_frame(const std::vector<data_frame::const_ptr> &dfs,
		bool in_mem)
{
	assert(!dfs.empty());
	size_t num_vecs = dfs[0]->get_num_vecs();
	for (size_t i = 1; i < dfs.size(); i++) {
		if (num_vecs != dfs[i]->get_num_vecs()) {
			BOOST_LOG_TRIVIAL(error)
				<< "The data frames have different numbers of vectors";
			return data_frame::ptr();
		}
	}

	data_frame::ptr df = data_frame::create();
	for (size_t vec_idx = 0; vec_idx < num_vecs; vec_idx++) {
		std::string vec_name = dfs[0]->named_vecs[vec_idx].first;
		const scalar_type &vec_type
			= dfs[0]->named_vecs[vec_idx].second->get_type();
		detail::vec_store::ptr vec = dfs[0]->named_vecs[vec_idx].second->deep_copy();

		// Here we collect the same column from all the data frame
		// except the first one.
		std::vector<detail::vec_store::const_ptr> vecs;
		for (size_t df_idx = 1; df_idx < dfs.size(); df_idx++) {
			if (vec_name != dfs[df_idx]->named_vecs[vec_idx].first
					|| vec_type != dfs[df_idx]->named_vecs[vec_idx].second->get_type()) {
				BOOST_LOG_TRIVIAL(error)
					<< "The data frames have different vectors";
				return data_frame::ptr();
			}
			vecs.push_back(dfs[df_idx]->named_vecs[vec_idx].second);
		}
		vec->append(vecs.begin(), vecs.end());
		df->add_vec(vec_name, vec);
	}
	return df;
}

std::vector<off_t> partition_vector(const detail::mem_vec_store &sorted_vec,
		int num_parts);

namespace
{

void expose_portion(sub_data_frame &sub_df, off_t loc, size_t length)
{
	for (size_t i = 0; i < sub_df.size(); i++)
		const_cast<local_vec_store *>(sub_df[i].get())->expose_sub_vec(loc,
				length);
}

class groupby_task_queue
{
	std::vector<off_t> par_starts;
	// This indicates the current task.
	std::atomic<size_t> curr_idx;
public:
	typedef std::shared_ptr<groupby_task_queue> ptr;

	struct task {
		// The start of the partition.
		off_t start;
		// The end of the partition.
		off_t end;
		// The index of the partition in the vector.
		size_t idx;

		task(off_t start, off_t end, size_t idx) {
			this->start = start;
			this->end = end;
			this->idx = idx;
		}

		bool is_valid() const {
			return start >= 0 && end > 0;
		}
	};

	groupby_task_queue(detail::mem_vec_store::const_ptr sorted_vec,
			size_t num_parts) {
		par_starts = partition_vector(*sorted_vec, num_parts);
		// It's possible that two partitions end up having the same start location
		// because the vector is small or a partition has only one value.
		assert(std::is_sorted(par_starts.begin(), par_starts.end()));
		auto end_par_starts = std::unique(par_starts.begin(), par_starts.end());
		par_starts.resize(end_par_starts - par_starts.begin());
		curr_idx = 0;
	}

	size_t get_num_parts() const {
		// The last one indicates the end of the vector for groupby.
		return par_starts.size() - 1;
	}

	task get_task() {
		size_t curr = curr_idx.fetch_add(1);
		if (curr >= get_num_parts())
			return task(-1, -1, -1);
		else
			return task(par_starts[curr], par_starts[curr + 1], curr);
	}
};

/*
 * It's not thread-safe to append data to a vector.
 * This class helps to append data to a vector in parallel.
 */
class vec_par_append
{
	std::map<off_t, detail::vec_store::const_ptr> buf;
	pthread_mutex_t lock;
	pthread_cond_t cond;

	detail::vec_store::ptr vec;
	std::atomic<size_t> num_threads;
public:
	typedef std::shared_ptr<vec_par_append> ptr;

	vec_par_append(detail::vec_store::ptr vec) {
		this->vec = vec;
		num_threads = detail::mem_thread_pool::get_global_num_threads();
		pthread_mutex_init(&lock, NULL);
		pthread_cond_init(&cond, NULL);
	}

	~vec_par_append() {
		pthread_mutex_destroy(&lock);
		pthread_cond_destroy(&cond);
	}

	void append(off_t idx, detail::vec_store::const_ptr vec) {
		pthread_mutex_lock(&lock);
		buf.insert(std::pair<off_t, detail::vec_store::const_ptr>(idx, vec));
		pthread_mutex_unlock(&lock);
		pthread_cond_signal(&cond);
	}

	void append_compl() {
		// One of the threads finishes appending data.
		num_threads--;
		pthread_cond_signal(&cond);
	}

	bool is_complete() const {
		return num_threads == 0;
	}

	off_t process(std::map<off_t, detail::vec_store::const_ptr> &lbuf,
			off_t last_idx) {
		// Get all of the vectors from other threads.
		pthread_mutex_lock(&lock);
		while (this->buf.empty() && !is_complete()) {
			pthread_cond_wait(&cond, &lock);
		}
		lbuf.insert(this->buf.begin(), this->buf.end());
		this->buf.clear();
		pthread_mutex_unlock(&lock);

		// Find a sequence of vectors with contiguous indices.
		auto it = lbuf.begin();
		std::vector<detail::vec_store::const_ptr> contig;
		while (it != lbuf.end() && last_idx + 1 == it->first) {
			contig.push_back(it->second);
			last_idx++;
			it++;
		}
		// Append these vectors to the global vector.
		if (it != lbuf.begin()) {
			lbuf.erase(lbuf.begin(), it);
			vec->append(contig.begin(), contig.end());
		}
		return last_idx;
	}

	void run() {
		std::map<off_t, detail::vec_store::const_ptr> lbuf;
		off_t last_idx = -1;
		printf("start to collect vecs\n");
		while (!is_complete()) {
			last_idx = process(lbuf, last_idx);
			printf("last vec: %ld\n", last_idx);
		}
		// Here all threads have appended all vectors. We should
		// have all of the vectors at this point.
		last_idx = process(lbuf, last_idx);

		printf("There are %ld vecs\n", lbuf.size());
		assert(lbuf.empty());
	}
};

class local_groupby_task: public thread_task
{
	groupby_task_queue::ptr q;
	off_t sorted_col_idx;
	std::vector<named_cvec_t> sorted_df;
	vec_par_append::ptr append;
	const gr_apply_operate<sub_data_frame> &op;
public:
	local_groupby_task(groupby_task_queue::ptr q, off_t sorted_col_idx,
			const std::vector<named_cvec_t> &sorted_df,
			const gr_apply_operate<sub_data_frame> &_op,
			vec_par_append::ptr append): op(_op) {
		this->q = q;
		this->sorted_col_idx = sorted_col_idx;
		this->sorted_df = sorted_df;
		this->append = append;
	}

	void run();
};

void local_groupby_task::run()
{
	struct timeval start, end;
	gettimeofday(&start, NULL);
	size_t num_tasks = 0;

	size_t out_size;
	// If the user can predict the number of output elements, we can create
	// a buffer of the expected size.
	if (op.get_num_out_eles() > 0)
		out_size = op.get_num_out_eles();
	else
		// If the user can't, we create a small buffer.
		out_size = 16;
	local_buf_vec_store row(0, out_size, op.get_output_type(), -1);
	while (true) {
		// Get the a partition from the queue.
		auto t = q->get_task();
		if (!t.is_valid())
			break;
		off_t start_ele = t.start;
		off_t end_ele = t.end;
		off_t idx = t.idx;
		num_tasks++;

		sub_data_frame sub_df(sorted_df.size());
		local_vec_store::const_ptr sub_sorted_col;
		for (size_t i = 0; i < sorted_df.size(); i++) {
			sub_df[i] = sorted_df[i].second->get_portion(start_ele,
					end_ele - start_ele);
			assert(sub_df[i]);
			if (i == (size_t) sorted_col_idx)
				sub_sorted_col = sub_df[i];
		}
		assert(sub_sorted_col);

		detail::mem_vv_store::ptr ret = detail::mem_vv_store::create(
				op.get_output_type());
		agg_operate::const_ptr find_next
			= sub_sorted_col->get_type().get_agg_ops().get_find_next();
		size_t loc = 0;
		size_t col_len = sub_sorted_col->get_length();
		// We can't search a vv store.
		assert(!detail::vv_store::is_vector_vector(*sub_sorted_col));
		const char *start = sub_sorted_col->get_raw_arr();
		size_t entry_size = sub_sorted_col->get_type().get_size();
		while (loc < col_len) {
			size_t curr_length = col_len - loc;
			const char *curr_ptr = start + entry_size * loc;
			size_t rel_end;
			find_next->runAgg(curr_length, curr_ptr, &rel_end);
			// This expose a portion of the data frame.
			expose_portion(sub_df, loc, rel_end);
			// The first argument is the key and the second one is the value
			// (a data frame)
			op.run(curr_ptr, sub_df, row);
			// TODO here is the memory allocation problem.
			// We don't know the length of the array in advance.
			if (row.get_length() > 0)
				ret->append(row);
			loc += rel_end;
		}
		append->append(idx, ret);
	}
	append->append_compl();
	gettimeofday(&end, NULL);
	printf("%ld tasks take %f seconds\n", num_tasks, time_diff(start, end));
}

}

static std::vector<detail::mem_vv_store::ptr> parallel_groupby(
		const std::vector<named_cvec_t> &sorted_df, off_t sorted_col_idx,
		const gr_apply_operate<sub_data_frame> &op)
{
	detail::mem_vec_store::const_ptr sorted_col
		= detail::mem_vec_store::cast(sorted_df[sorted_col_idx].second);
	// We need to find the start location for each thread.
	// The start location is where the value in the sorted array
	// first appears.
	// TODO this only works for vectors stored contiguously in memory.
	// It doesn't work for NUMA vector.
	detail::mem_thread_pool::ptr mem_threads
		= detail::mem_thread_pool::get_global_mem_threads();
	int num_threads = mem_threads->get_num_threads();
	int num_parts = num_threads;
	// If the vector is large, we should divide it into many more parts to have
	// better load balancing.
	if (sorted_col->get_length() >= 1000000)
		num_parts *= 10;

	groupby_task_queue::ptr q(new groupby_task_queue(sorted_col, num_parts));

	detail::mem_vv_store::ptr result = detail::mem_vv_store::create(
			op.get_output_type());
	vec_par_append::ptr append(new vec_par_append(result));
	for (int i = 0; i < num_threads; i++) {
		// It's difficult to localize computation.
		// TODO can we localize computation?
		int node_id = i % mem_threads->get_num_nodes();
		mem_threads->process_task(node_id, new local_groupby_task(
					q, sorted_col_idx, sorted_df, op, append));
	}
	append->run();
	mem_threads->wait4complete();
	return std::vector<detail::mem_vv_store::ptr>(1, result);
}

static vector_vector::ptr in_mem_groupby(
		data_frame::const_ptr sorted_df, const std::string &col_name,
		const gr_apply_operate<sub_data_frame> &op)
{
	std::vector<named_cvec_t> df_vecs(sorted_df->get_num_vecs());
	off_t sorted_col_idx = -1;
	for (size_t i = 0; i < df_vecs.size(); i++) {
		df_vecs[i].first = sorted_df->get_vec_name(i);
		df_vecs[i].second = sorted_df->get_vec(i);
		if (df_vecs[i].first == col_name)
			sorted_col_idx = i;
	}
	assert(sorted_col_idx >= 0);

	std::vector<detail::mem_vv_store::ptr> sub_results = parallel_groupby(
			df_vecs, sorted_col_idx, op);
	if (sub_results.size() == 1)
		return vector_vector::create(sub_results[0]);
	else {
		detail::mem_vv_store::ptr res_vv = sub_results[0];
		std::vector<detail::vec_store::const_ptr> remain;
		for (auto it = sub_results.begin() + 1; it != sub_results.end(); it++)
			if (*it != NULL)
				remain.push_back(*it);
		bool ret = res_vv->append(remain.begin(), remain.end());
		assert(ret);
		return vector_vector::create(res_vv);
	}
}

namespace
{

class EM_df_groupby_dispatcher: public detail::task_dispatcher
{
	off_t ele_idx;
	size_t portion_size;
	std::string col_name;
	detail::vec_store::const_ptr groupby_col;
	data_frame::const_ptr df;
	detail::EM_vv_store::ptr out_vv;
	const gr_apply_operate<sub_data_frame> &op;
public:
	EM_df_groupby_dispatcher(data_frame::const_ptr df, const std::string &col_name,
			detail::EM_vv_store::ptr out_vv, size_t portion_size,
			const gr_apply_operate<sub_data_frame> &_op): op(_op) {
		ele_idx = 0;
		this->portion_size = portion_size;
		this->col_name = col_name;
		this->groupby_col = df->get_vec(col_name);
		this->df = df;
		this->out_vv = out_vv;
	}

	virtual bool issue_task();
};

bool EM_df_groupby_dispatcher::issue_task()
{
	if ((size_t) ele_idx >= groupby_col->get_length())
		return false;

	// Indicate whether this portion is the last portion in the vector.
	bool last_part;
	// The number of elements we need to read from the sorted vector.
	size_t read_len;
	// The number of elements we need to expose on the vectors.
	size_t real_len;
	if (portion_size >= groupby_col->get_length() - ele_idx) {
		last_part = true;
		read_len = groupby_col->get_length() - ele_idx;
	}
	else {
		last_part = false;
		read_len = portion_size;
	}
	real_len = read_len;

	local_vec_store::const_ptr vec = groupby_col->get_portion(ele_idx, read_len);
	// If this isn't the last portion, we should expose the part of
	// the sorted vector that all elements with the same values in the vector
	// are guaranteed in the part.
	if (!last_part) {
		agg_operate::const_ptr find_prev
			= vec->get_type().get_agg_ops().get_find_prev();
		size_t off;
		size_t entry_size = vec->get_type().get_size();
		find_prev->runAgg(read_len, vec->get_raw_arr() + read_len * entry_size,
				&off);
		// All keys are the same in this portion of the vector. Then we don't
		// know if we have got all values for the key.
		// If we know we can ignore the key, we can ignore the entire portion.
		if (off == read_len && op.ignore_key(vec->get_raw_arr()))
			off = 0;
		// Otherwise, we have to make sure we have seen all values for the keys
		// we are going to run UDFs.
		else
			assert(off < read_len);
		real_len = read_len - off;
		// The local buffer may already be a sub vector.
		const_cast<local_vec_store &>(*vec).expose_sub_vec(vec->get_local_start(),
				real_len);
	}

	// TODO it should fetch the rest of columns asynchronously.
	std::vector<named_cvec_t> df_vecs(df->get_num_vecs());
	off_t sorted_col_idx = -1;
	for (size_t i = 0; i < df->get_num_vecs(); i++) {
		if (df->get_vec_name(i) == col_name) {
			df_vecs[i].first = col_name;
			df_vecs[i].second = vec;
			sorted_col_idx = i;
		}
		else {
			local_vec_store::const_ptr col = df->get_vec(i)->get_portion(
					ele_idx, real_len);
			df_vecs[i].first = df->get_vec_name(i);
			df_vecs[i].second = col;
		}
		assert(df_vecs[i].second->get_length() == real_len);
	}

	assert(sorted_col_idx >= 0);
	std::vector<detail::mem_vv_store::ptr> sub_vv_results = parallel_groupby(
			df_vecs, sorted_col_idx, op);
	std::vector<detail::vec_store::const_ptr> res(sub_vv_results.begin(),
			sub_vv_results.end());
	// TODO data should also be written back asynchronously.
	out_vv->append(res.begin(), res.end());

	ele_idx += real_len;
	return true;
}

}

static vector_vector::ptr EM_groupby(
		data_frame::const_ptr sorted_df, const std::string &col_name,
		const gr_apply_operate<sub_data_frame> &op)
{
	detail::EM_vv_store::ptr out_vv = detail::EM_vv_store::create(
			op.get_output_type());

	size_t groupby_entry_size
		= sorted_df->get_vec_ref(col_name).get_type().get_size();
	size_t portion_size = matrix_conf.get_groupby_buf_size() / groupby_entry_size;
	// If one of the columns in the data frame is a vector vector,
	// we should use a smaller portion size.
	// TODO maybe there is a better way.
	for (size_t i = 0; i < sorted_df->get_num_vecs(); i++)
		if (sorted_df->get_vec_ref(i).get_entry_size() == 0) {
			portion_size = matrix_conf.get_vv_groupby_buf_size();
			break;
		}

	EM_df_groupby_dispatcher::ptr groupby_dispatcher(
			new EM_df_groupby_dispatcher(sorted_df, col_name, out_vv,
				portion_size, op));
	detail::io_worker_task worker(groupby_dispatcher, 1);
	for (size_t i = 0; i < sorted_df->get_num_vecs(); i++) {
		detail::vec_store::const_ptr col = sorted_df->get_vec(i);
		const detail::EM_object *obj
			= dynamic_cast<const detail::EM_object *>(col.get());
		worker.register_EM_obj(const_cast<detail::EM_object *>(obj));
	}
	worker.register_EM_obj(out_vv.get());
	worker.run();
	return vector_vector::create(out_vv);
}

vector_vector::ptr data_frame::groupby(const std::string &col_name,
		const gr_apply_operate<sub_data_frame> &op) const
{
	data_frame::const_ptr sorted_df = sort(col_name);
	if (named_vecs.front().second->is_in_mem())
		return in_mem_groupby(sorted_df, col_name, op);
	else
		return EM_groupby(sorted_df, col_name, op);
}

}
