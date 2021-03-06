#include <vector>

#include "caffe/filler.hpp"
#include "caffe/layers/inner_product_layer.hpp"
#include "caffe/util/math_functions.hpp"

namespace caffe {

template <typename Dtype>
void InnerProductLayer<Dtype>::Forward_gpu(const vector<Blob<Dtype>*>& bottom,
    const vector<Blob<Dtype>*>& top) {
  Dtype* bottom_data = bottom[0]->mutable_gpu_data();
  //<--CUSTOMIZATION
  const int count_b = bottom[0]->count();
  if (input_scale_ != Dtype(1)) {
    caffe_gpu_scal(count_b, input_scale_, bottom_data);
  }
  //CUSTOMIZATION-->
  Dtype* top_data = top[0]->mutable_gpu_data();
  const Dtype* weight = this->blobs_[0]->gpu_data();
  if (M_ == 1) {
    caffe_gpu_gemv<Dtype>(CblasNoTrans, N_, K_, (Dtype)1.,
                         weight, bottom_data, (Dtype)0., top_data);
    if (bias_term_)
      caffe_gpu_axpy<Dtype>(N_, bias_multiplier_.cpu_data()[0],
                            this->blobs_[1]->gpu_data(), top_data);
  } else {
    caffe_gpu_gemm<Dtype>(CblasNoTrans,
                          transpose_ ? CblasNoTrans : CblasTrans,
                          M_, N_, K_, (Dtype)1.,
                          bottom_data, weight, (Dtype)0., top_data);
    if (bias_term_)
      caffe_gpu_gemm<Dtype>(CblasNoTrans, CblasNoTrans, M_, N_, 1, (Dtype)1.,
                            bias_multiplier_.gpu_data(),
                            this->blobs_[1]->gpu_data(), (Dtype)1., top_data);
  }
  //<--CUSTOMIZATION
    const int count_t = top[0]->count();
    if (output_scale_ != Dtype(1)) {
      caffe_gpu_scal(count_t, output_scale_, top_data);
      caffe_gpu_round(count_t, top_data);
    }
  //CUSTOMIZATION-->
}

template <typename Dtype>
void InnerProductLayer<Dtype>::Backward_gpu(const vector<Blob<Dtype>*>& top,
    const vector<bool>& propagate_down,
    const vector<Blob<Dtype>*>& bottom) {
  if (this->param_propagate_down_[0]) {
    const Dtype* top_diff = top[0]->gpu_diff();
    const Dtype* bottom_data = bottom[0]->gpu_data();
	update_weight_ = true;
    if (this->layer_param_.inner_product_param().gen_mode() && gan_mode_ != 2) {
      update_weight_ = false;
    }
    if (this->layer_param_.inner_product_param().dis_mode() && gan_mode_ == 2) {
      update_weight_ = false;
    }
    // Gradient with respect to weight
    if (transpose_) {
      if (update_weight_) {
        caffe_gpu_gemm<Dtype>(CblasTrans, CblasNoTrans,
          K_, N_, M_,
          (Dtype)1., bottom_data, top_diff,
          (Dtype)1., this->blobs_[0]->mutable_gpu_diff());
      }
    } else {
      if (update_weight_) {
        caffe_gpu_gemm<Dtype>(CblasTrans, CblasNoTrans,
          N_, K_, M_,
          (Dtype)1., top_diff, bottom_data,
          (Dtype)1., this->blobs_[0]->mutable_gpu_diff());
      }
    }
  }
  if (bias_term_ && this->param_propagate_down_[1] && update_weight_) {
    const Dtype* top_diff = top[0]->gpu_diff();
    // Gradient with respect to bias
    caffe_gpu_gemv<Dtype>(CblasTrans, M_, N_, (Dtype)1., top_diff,
        bias_multiplier_.gpu_data(), (Dtype)1.,
        this->blobs_[1]->mutable_gpu_diff());
  }
  if (propagate_down[0]) {
    const Dtype* top_diff = top[0]->gpu_diff();
    // Gradient with respect to bottom data
    if (transpose_) {
      caffe_gpu_gemm<Dtype>(CblasNoTrans, CblasTrans,
        M_, K_, N_,
        (Dtype)1., top_diff, this->blobs_[0]->gpu_data(),
        (Dtype)0., bottom[0]->mutable_gpu_diff());
    } else {
      caffe_gpu_gemm<Dtype>(CblasNoTrans, CblasNoTrans,
        M_, K_, N_,
        (Dtype)1., top_diff, this->blobs_[0]->gpu_data(),
        (Dtype)0., bottom[0]->mutable_gpu_diff());
    }
  }
  // update gan_mode_
  gan_mode_ = gan_mode_ == 2 ? 1 : gan_mode_ + 1;
}

INSTANTIATE_LAYER_GPU_FUNCS(InnerProductLayer);

}  // namespace caffe
