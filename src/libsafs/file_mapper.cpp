/*
 * Copyright 2014 Open Connectome Project (http://openconnecto.me)
 * Written by Da Zheng (zhengda1936@gmail.com)
 *
 * This file is part of SAFSlib.
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

#include "file_mapper.h"

namespace safs
{

int gen_RAID_rand_start(int num_files)
{
	int r = random();
	while (r == 0) {
		r = random();
	}
	return r % num_files;
}

int RAID0_mapper::rand_start;
int RAID5_mapper::rand_start;

atomic_integer file_mapper::file_id_gen;

}
