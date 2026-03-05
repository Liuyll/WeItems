//
//  AddItemView.swift
//  WeItems
//

import SwiftUI
import PhotosUI

struct AddItemView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ItemStore
    @ObservedObject var groupStore: GroupStore
    
    var defaultGroupId: UUID?
    
    @State private var name = ""
    @State private var details = ""
    @State private var purchaseLink = ""
    @State private var price = ""
    @State private var selectedType: ItemType = .other
    @State private var selectedGroupId: UUID?
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    
    @State private var showingAddGroup = false
    
    private var isValid: Bool {
        !name.isEmpty && !price.isEmpty && Double(price) != nil
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // 基本信息
                Section("基本信息") {
                    TextField("物品名称", text: $name)
                    
                    HStack {
                        Text("¥")
                            .foregroundStyle(.secondary)
                        TextField("价格", text: $price)
                            .keyboardType(.decimalPad)
                    }
                    
                    Picker("类型", selection: $selectedType) {
                        ForEach(ItemType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                }
                
                // 分组选择
                Section("所属分组") {
                    if groupStore.groups.isEmpty {
                        Button {
                            showingAddGroup = true
                        } label: {
                            Label("创建分组", systemImage: "folder.badge.plus")
                        }
                    } else {
                        Picker("选择分组", selection: $selectedGroupId) {
                            Text("无分组")
                                .tag(nil as UUID?)
                            
                            ForEach(groupStore.groups) { group in
                                Label(group.name, systemImage: group.icon)
                                    .tag(group.id as UUID?)
                            }
                        }
                        
                        Button {
                            showingAddGroup = true
                        } label: {
                            Label("新建分组", systemImage: "folder.badge.plus")
                        }
                    }
                }
                
                // 图片选择
                Section("图片") {
                    VStack(spacing: 16) {
                        if let imageData = selectedImageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 200)
                                .overlay(
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo.badge.plus")
                                            .font(.system(size: 40))
                                            .foregroundStyle(.gray)
                                        Text("选择图片")
                                            .foregroundStyle(.secondary)
                                    }
                                )
                        }
                        
                        PhotosPicker(selection: $selectedPhoto,
                                   matching: .images) {
                            Label(selectedImageData == nil ? "选择照片" : "更换照片",
                                  systemImage: "photo")
                                .frame(maxWidth: .infinity)
                        }
                        .onChange(of: selectedPhoto) { _, newValue in
                            Task {
                                if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                    selectedImageData = data
                                }
                            }
                        }
                        
                        if selectedImageData != nil {
                            Button(role: .destructive) {
                                selectedImageData = nil
                                selectedPhoto = nil
                            } label: {
                                Label("删除图片", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // 详情
                Section("详情描述") {
                    TextEditor(text: $details)
                        .frame(minHeight: 80)
                }
                
                // 购买链接
                Section("购买链接") {
                    TextField("输入链接地址", text: $purchaseLink)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle("添加物品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveItem()
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingAddGroup) {
                AddGroupView(groupStore: groupStore)
            }
            .onAppear {
                selectedGroupId = defaultGroupId
            }
        }
    }
    
    private func saveItem() {
        guard let priceValue = Double(price) else { return }
        
        let newItem = Item(
            name: name,
            details: details,
            purchaseLink: purchaseLink,
            imageData: selectedImageData,
            price: priceValue,
            type: selectedType.rawValue,
            groupId: selectedGroupId
        )
        
        store.add(newItem)
        dismiss()
    }
}

#Preview {
    AddItemView(store: ItemStore(), groupStore: GroupStore())
}
